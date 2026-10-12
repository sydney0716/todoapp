from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import and_, func, or_, select, text
from sqlalchemy.orm import Session, selectinload

from ..database import get_db
from ..models import (
    PurgedTask,
    Subtask,
    SyncEvent,
    Task,
    User,
    WorkspaceMember,
)
from ..models import (
    SyncOperation as DbSyncOperation,
)
from ..models import (
    Visibility as DbVisibility,
)
from ..schemas import (
    SubtaskRecord,
    SyncBootstrapResponse,
    SyncOperation,
    SyncPullResponse,
    SyncPushRequest,
    SyncPushResponse,
    TaskChange,
    TaskRecord,
    Visibility,
)
from ..security import CurrentUser, require_user

router = APIRouter(prefix="/sync", tags=["sync"])
_CURRENT_USER_DEPENDENCY = Depends(require_user)
_DB_DEPENDENCY = Depends(get_db)
_TASK_FIELD_NAMES = (
    "owner_user_id",
    "visibility",
    "workspace_id",
    "created_by_user_id",
    "title",
    "note",
    "category",
    "is_completed",
    "shared_completion_mode",
    "completed_by_user_ids",
    "due_at",
    "reminder_option",
    "reminder_value",
    "deleted_at",
)


@router.get("/bootstrap", response_model=SyncBootstrapResponse)
def bootstrap(
    current_user: CurrentUser = _CURRENT_USER_DEPENDENCY,
    db: Session = _DB_DEPENDENCY,
) -> SyncBootstrapResponse:
    _lock_sync_writers(db)
    tasks = db.scalars(
        select(Task)
        .options(selectinload(Task.subtasks))
        .where(_visible_task_filter(current_user.user_id))
        .order_by(Task.updated_at.asc(), Task.sync_id.asc())
    ).all()
    return SyncBootstrapResponse(
        cursor=_current_cursor(db),
        tasks=[_task_to_record(task) for task in tasks],
    )


@router.get("/tasks", response_model=SyncPullResponse)
def pull_tasks(
    cursor: str | None = Query(default=None),
    current_user: CurrentUser = _CURRENT_USER_DEPENDENCY,
    db: Session = _DB_DEPENDENCY,
) -> SyncPullResponse:
    cursor_id = _parse_cursor(cursor)
    events = db.scalars(
        select(SyncEvent)
        .where(
            SyncEvent.visible_user_id == current_user.user_id,
            SyncEvent.id > cursor_id,
        )
        .order_by(SyncEvent.id.asc())
        .limit(501)
    ).all()

    has_more = len(events) > 500
    events = events[:500]
    visible_changes = [
        event
        for event in events
        if event.origin_device_id is None
        or current_user.device_id is None
        or event.origin_device_id != current_user.device_id
    ]
    changes = [_event_to_change(event) for event in visible_changes]
    return SyncPullResponse(
        cursor=str(events[-1].id) if events else str(cursor_id),
        changes=changes,
        has_more=has_more,
    )


@router.post("/tasks", response_model=SyncPushResponse)
def push_tasks(
    payload: SyncPushRequest,
    current_user: CurrentUser = _CURRENT_USER_DEPENDENCY,
    db: Session = _DB_DEPENDENCY,
) -> SyncPushResponse:
    if (
        current_user.device_id is not None
        and payload.device_id != current_user.device_id
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Sync payload device_id does not match bearer token",
        )

    _lock_sync_writers(db)
    accepted: list[TaskRecord] = []
    rejected: list[str] = []
    purged_ids: list[UUID] = []

    for change in payload.changes:
        try:
            with db.begin_nested():
                previous_record = _existing_task_record(db, change.record.id)
                previous_visible_user_ids = (
                    set(_visible_user_ids(db, previous_record))
                    if previous_record is not None
                    else set()
                )
                record, changed_task_fields, changed_subtask_ids = _apply_task_change(
                    db, current_user, change
                )
                if (
                    change.operation == SyncOperation.purge
                    or changed_task_fields
                    or changed_subtask_ids
                ):
                    visible_user_ids = (
                        previous_visible_user_ids
                        if change.operation == SyncOperation.purge
                        else set(_visible_user_ids(db, record))
                    )
                    for visible_user_id in visible_user_ids:
                        _add_sync_event(
                            db,
                            visible_user_id=visible_user_id,
                            operation=change.operation,
                            record=record,
                            origin_device_id=payload.device_id,
                            changed_task_fields=changed_task_fields,
                            changed_subtask_ids=changed_subtask_ids,
                        )
                    if (
                        change.operation != SyncOperation.purge
                        and previous_record is not None
                    ):
                        lost_user_ids = previous_visible_user_ids - visible_user_ids
                        for visible_user_id in lost_user_ids:
                            _add_sync_event(
                                db,
                                visible_user_id=visible_user_id,
                                operation=SyncOperation.purge,
                                record=previous_record,
                                origin_device_id=payload.device_id,
                                changed_task_fields=[],
                                changed_subtask_ids=[],
                            )
        except TaskAlreadyPurged:
            purged_ids.append(change.record.id)
            continue
        except ValueError as error:
            rejected.append(str(error))
            continue

        accepted.append(record)

    db.commit()
    return SyncPushResponse(
        cursor=_current_cursor(db),
        accepted=accepted,
        rejected=rejected,
        purged_ids=purged_ids,
    )


class TaskAlreadyPurged(ValueError):
    pass


def _lock_sync_writers(db: Session) -> None:
    # IDs must be committed in allocation order. Bootstrap uses the same lock so
    # its tasks and cursor describe one state even at READ COMMITTED isolation.
    if getattr(db, "bind", None) is not None and db.bind.dialect.name == "postgresql":
        db.execute(text("SELECT pg_advisory_xact_lock(741802341)"))


def _parse_cursor(cursor: str | None) -> int:
    if cursor is None or cursor == "":
        return 0
    try:
        cursor_id = int(cursor)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="cursor must be an integer event id",
        ) from None
    if cursor_id < 0:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="cursor must be an integer event id",
        )
    return cursor_id


def _current_cursor(db: Session) -> str:
    cursor = db.scalar(select(func.coalesce(func.max(SyncEvent.id), 0)))
    return str(cursor or 0)


def _event_to_change(event: SyncEvent) -> TaskChange:
    return TaskChange(
        operation=SyncOperation(event.operation.value),
        record=TaskRecord.model_validate(event.payload),
        event_id=event.id,
        origin_device_id=event.origin_device_id,
        changed_task_fields=list(event.changed_task_fields or []),
        changed_subtask_ids=[
            UUID(str(subtask_id)) for subtask_id in event.changed_subtask_ids or []
        ],
    )


def _existing_task_record(db: Session, task_id: UUID) -> TaskRecord | None:
    task = db.get(Task, task_id)
    if task is None:
        return None
    return _task_to_record(task, subtasks=_task_subtasks(db, task))


def _add_sync_event(
    db: Session,
    *,
    visible_user_id: UUID,
    operation: SyncOperation,
    record: TaskRecord,
    origin_device_id: UUID,
    changed_task_fields: list[str],
    changed_subtask_ids: list[UUID],
) -> None:
    db.add(
        SyncEvent(
            visible_user_id=visible_user_id,
            entity_type="task",
            entity_sync_id=record.id,
            operation=DbSyncOperation(operation.value),
            origin_device_id=origin_device_id,
            changed_task_fields=changed_task_fields,
            changed_subtask_ids=[str(subtask_id) for subtask_id in changed_subtask_ids],
            payload=record.model_dump(mode="json"),
        )
    )


def _visible_task_filter(user_id: UUID):
    shared_workspace_ids = select(WorkspaceMember.workspace_id).where(
        WorkspaceMember.user_id == user_id
    )
    return or_(
        and_(Task.visibility == DbVisibility.private, Task.owner_user_id == user_id),
        and_(
            Task.visibility == DbVisibility.shared,
            Task.workspace_id.in_(shared_workspace_ids),
        ),
    )


def _task_to_record(
    task: Task,
    subtasks: list[Subtask] | None = None,
) -> TaskRecord:
    if task.device_id is None:
        raise ValueError(f"Task {task.sync_id} is missing device_id")
    task_subtasks = task.subtasks if subtasks is None else subtasks
    return TaskRecord(
        id=task.sync_id,
        owner_user_id=task.owner_user_id,
        visibility=Visibility(task.visibility.value),
        workspace_id=task.workspace_id,
        title=task.title,
        note=task.note,
        category=task.category,
        is_completed=task.is_completed,
        completed_at=task.completed_at,
        shared_completion_mode=task.shared_completion_mode,
        completed_by_user_ids=[
            UUID(str(user_id)) for user_id in task.completed_by_user_ids or []
        ],
        due_at=task.due_at,
        reminder_option=task.reminder_option,
        reminder_value=task.reminder_value,
        created_at=task.created_at,
        updated_at=task.updated_at,
        version=task.version,
        deleted_at=task.deleted_at,
        purge_after=task.purge_after,
        created_by_user_id=task.created_by_user_id,
        updated_by_user_id=task.updated_by_user_id,
        device_id=task.device_id,
        subtasks=[
            SubtaskRecord(
                id=subtask.sync_id,
                task_id=subtask.task_sync_id,
                title=subtask.title,
                is_completed=subtask.is_completed,
                due_at=subtask.due_at,
                position=subtask.position,
                created_at=subtask.created_at,
                updated_at=subtask.updated_at,
                version=subtask.version,
                deleted_at=subtask.deleted_at,
            )
            for subtask in sorted(
                task_subtasks,
                key=lambda item: (item.position, item.created_at, str(item.sync_id)),
            )
        ],
    )


def _apply_task_change(
    db: Session,
    current_user: CurrentUser,
    change: TaskChange,
) -> tuple[TaskRecord, list[str], list[UUID]]:
    record = change.record
    accepted_at = datetime.now(UTC)
    _validate_record_access(
        db,
        current_user,
        record,
        enforce_record_device=change.operation != SyncOperation.purge,
    )

    tombstone = db.get(PurgedTask, record.id)
    if tombstone is not None:
        if tombstone.owner_user_id != current_user.user_id and (
            tombstone.workspace_id is None
            or db.scalar(
                select(WorkspaceMember).where(
                    WorkspaceMember.workspace_id == tombstone.workspace_id,
                    WorkspaceMember.user_id == current_user.user_id,
                )
            )
            is None
        ):
            raise ValueError(f"Task {record.id} is not visible to the caller")
        raise TaskAlreadyPurged(str(record.id))

    existing = db.get(Task, record.id)
    if existing is not None and not _task_visible_to_user(
        db, existing, current_user.user_id
    ):
        raise ValueError(f"Task {record.id} is not visible to the caller")
    if existing is not None and (
        record.owner_user_id != existing.owner_user_id
        or (
            current_user.user_id != existing.owner_user_id
            and (
                record.visibility.value != existing.visibility.value
                or record.workspace_id != existing.workspace_id
            )
        )
    ):
        raise ValueError(
            f"Task {record.id} ownership or visibility cannot be changed by this user"
        )
    child_ids: set[UUID] = set()
    for child in record.subtasks:
        if child.task_id != record.id or child.id in child_ids:
            raise ValueError(f"Task {record.id} has invalid or duplicate subtasks")
        child_ids.add(child.id)
        stored_child = db.get(Subtask, child.id)
        if stored_child is not None and stored_child.task_sync_id != record.id:
            raise ValueError(f"Subtask {child.id} already belongs to another task")
    if change.operation == SyncOperation.purge:
        task = db.get(Task, record.id)
        if task is not None:
            if task.owner_user_id != current_user.user_id:
                raise ValueError(f"Task {record.id} cannot be purged by this user")
            if task.deleted_at is None:
                raise ValueError(f"Task {record.id} cannot be purged before trash")
            if task.purge_after is None or task.purge_after > accepted_at:
                raise ValueError(
                    f"Task {record.id} cannot be purged before retention expires"
                )
            deleted_record = _task_to_record(task, subtasks=_task_subtasks(db, task))
            db.add(
                PurgedTask(
                    sync_id=task.sync_id,
                    owner_user_id=task.owner_user_id,
                    workspace_id=task.workspace_id,
                    purged_at=accepted_at,
                )
            )
            db.delete(task)
            return deleted_record, [], []
        if record.owner_user_id != current_user.user_id:
            raise ValueError(f"Task {record.id} cannot be purged by this user")
        db.add(
            PurgedTask(
                sync_id=record.id,
                owner_user_id=record.owner_user_id,
                workspace_id=record.workspace_id,
                purged_at=accepted_at,
            )
        )
        return record, [], []

    record = _merge_completion(db, existing, current_user, change)
    deleted_at = record.deleted_at
    changed_task_fields = _normalized_changed_task_fields(
        existing,
        record,
        deleted_at=deleted_at,
        requested_fields=change.changed_task_fields,
    )
    if (
        existing is not None
        and change.changed_task_fields is not None
        and any(
            field in change.changed_task_fields
            for field in (
                "is_completed",
                "completed_by_user_ids",
                "shared_completion_mode",
            )
        )
    ):
        for field in ("is_completed", "completed_by_user_ids"):
            if (
                _task_field_changed(existing, record, field, deleted_at=deleted_at)
                and field not in changed_task_fields
            ):
                changed_task_fields.append(field)
    changed_task_field_set = set(changed_task_fields)
    incoming_delete = "deleted_at" in changed_task_field_set and deleted_at is not None
    incoming_restore = "deleted_at" in changed_task_field_set and deleted_at is None
    existing_deleted = existing is not None and existing.deleted_at is not None
    stale_child_or_field_change_for_deleted_task = (
        existing_deleted and not incoming_delete and not incoming_restore
    )
    if stale_child_or_field_change_for_deleted_task:
        changed_task_fields = []
        changed_task_field_set = set()

    if incoming_delete:
        changed_task_fields = ["deleted_at"]
        changed_task_field_set = {"deleted_at"}

    changed_subtask_ids = (
        []
        if stale_child_or_field_change_for_deleted_task
        or (
            incoming_delete
            and existing is not None
            and change.changed_subtask_ids is None
        )
        else _normalized_changed_subtask_ids(existing, change)
    )
    task = existing
    if task is None:
        task = Task(sync_id=record.id)
        db.add(task)
    task_fields_changed = existing is None or bool(changed_task_field_set)
    was_completed = bool(existing.is_completed) if existing is not None else False
    if existing is None or task_fields_changed:
        server_deleted_at = _server_deleted_at(record, deleted_at, accepted_at)
        _apply_task_fields(
            task,
            record,
            changed_fields=changed_task_field_set,
            server_deleted_at=server_deleted_at,
            accepted_at=accepted_at,
            is_new=existing is None,
        )

    existing_subtasks = {
        subtask.sync_id: subtask
        for subtask in db.scalars(
            select(Subtask).where(Subtask.task_sync_id == record.id)
        )
    }
    changed_subtask_id_set = set(changed_subtask_ids)
    applied_subtask_ids: list[UUID] = []
    for subtask_record in record.subtasks:
        if subtask_record.id not in changed_subtask_id_set:
            continue
        subtask = existing_subtasks.get(subtask_record.id)
        is_new_subtask = subtask is None
        if subtask is None:
            subtask = Subtask(
                sync_id=subtask_record.id,
                task_sync_id=record.id,
                created_at=subtask_record.created_at or accepted_at,
            )
            db.add(subtask)
        elif change.changed_subtask_ids is None and not _legacy_incoming_subtask_wins(
            subtask, subtask_record
        ):
            continue

        subtask.task_sync_id = record.id
        subtask.title = subtask_record.title
        subtask.is_completed = subtask_record.is_completed
        subtask.due_at = subtask_record.due_at
        subtask.position = subtask_record.position
        subtask.updated_at = accepted_at
        subtask.version = 1 if is_new_subtask else subtask.version + 1
        subtask.deleted_at = (
            accepted_at if subtask_record.deleted_at is not None else None
        )
        subtask.server_updated_at = accepted_at
        applied_subtask_ids.append(subtask_record.id)

    if applied_subtask_ids and not task_fields_changed:
        task.version += 1
        task.updated_at = accepted_at
        task.updated_by_user_id = current_user.user_id
        task.device_id = record.device_id
        task.server_updated_at = accepted_at
    if task_fields_changed:
        task.updated_by_user_id = current_user.user_id
        if task.is_completed and not was_completed:
            task.completed_at = accepted_at
        elif not task.is_completed:
            task.completed_at = None
    db.flush()
    return (
        _task_to_record(task, subtasks=_task_subtasks(db, task)),
        changed_task_fields,
        applied_subtask_ids,
    )


def _merge_completion(
    db: Session,
    existing: Task | None,
    current_user: CurrentUser,
    change: TaskChange,
) -> TaskRecord:
    record = change.record
    requested = change.changed_task_fields
    completion_requested = (
        existing is None
        or requested is None
        or any(
            field in requested
            for field in (
                "is_completed",
                "completed_by_user_ids",
                "shared_completion_mode",
            )
        )
    )
    if not completion_requested:
        return record
    mode = (
        record.shared_completion_mode.value
        if (
            existing is None
            or requested is None
            or "shared_completion_mode" in requested
        )
        else existing.shared_completion_mode
    )
    visibility = (
        record.visibility.value
        if (existing is None or requested is None or "visibility" in requested)
        else existing.visibility.value
    )
    if visibility != "shared" or mode != "both":
        return record
    completed = set(_completed_by_user_ids(existing)) if existing is not None else set()
    caller_id = str(current_user.user_id)
    if (
        existing is None
        or requested is None
        or "is_completed" in requested
        or "completed_by_user_ids" in requested
    ):
        if caller_id in _record_completed_by_user_ids(record):
            completed.add(caller_id)
        else:
            completed.discard(caller_id)
    members = {str(user_id) for user_id in _visible_user_ids(db, record)}
    completed &= members
    return record.model_copy(
        update={
            "completed_by_user_ids": [UUID(user_id) for user_id in sorted(completed)],
            "is_completed": bool(members) and members <= completed,
        }
    )


def _normalized_changed_task_fields(
    existing: Task | None,
    record: TaskRecord,
    *,
    deleted_at: datetime | None,
    requested_fields: list[str] | None,
) -> list[str]:
    if existing is None:
        return list(_TASK_FIELD_NAMES)
    if requested_fields is not None:
        changed_fields = [
            field
            for field in requested_fields
            if field in _TASK_FIELD_NAMES
            and _task_field_changed(existing, record, field, deleted_at=deleted_at)
        ]
        return changed_fields

    changed_fields: list[str] = []
    for field_name in _TASK_FIELD_NAMES:
        if _task_field_changed(existing, record, field_name, deleted_at=deleted_at):
            changed_fields.append(field_name)
    return changed_fields if _legacy_incoming_task_wins(existing, record) else []


def _normalized_changed_subtask_ids(
    existing: Task | None,
    change: TaskChange,
) -> list[UUID]:
    if existing is None:
        return [subtask.id for subtask in change.record.subtasks]
    if change.changed_subtask_ids is not None:
        return list(change.changed_subtask_ids)
    return [subtask.id for subtask in change.record.subtasks]


def _legacy_incoming_task_wins(existing: Task, record: TaskRecord) -> bool:
    return record.version >= existing.version


def _legacy_incoming_subtask_wins(existing: Subtask, record: SubtaskRecord) -> bool:
    return record.version >= existing.version


def _task_field_changed(
    task: Task,
    record: TaskRecord,
    field_name: str,
    *,
    deleted_at: datetime | None,
) -> bool:
    match field_name:
        case "owner_user_id":
            return task.owner_user_id != record.owner_user_id
        case "visibility":
            return task.visibility != DbVisibility(record.visibility.value)
        case "workspace_id":
            return task.workspace_id != record.workspace_id
        case "created_by_user_id":
            return task.created_by_user_id != record.created_by_user_id
        case "title":
            return task.title != record.title
        case "note":
            return task.note != record.note
        case "category":
            return task.category != record.category
        case "is_completed":
            return task.is_completed != record.is_completed
        case "shared_completion_mode":
            return task.shared_completion_mode != record.shared_completion_mode.value
        case "completed_by_user_ids":
            return _completed_by_user_ids(task) != _record_completed_by_user_ids(record)
        case "due_at":
            return task.due_at != record.due_at
        case "reminder_option":
            return task.reminder_option != record.reminder_option
        case "reminder_value":
            return task.reminder_value != record.reminder_value
        case "deleted_at":
            return (task.deleted_at is None) != (deleted_at is None)
    return False


def _apply_task_fields(
    task: Task,
    record: TaskRecord,
    *,
    changed_fields: set[str] | None,
    server_deleted_at: datetime | None,
    accepted_at: datetime,
    is_new: bool,
) -> None:
    if is_new or _should_apply_task_field(changed_fields, "owner_user_id"):
        task.owner_user_id = record.owner_user_id
    if is_new or _should_apply_task_field(changed_fields, "visibility"):
        task.visibility = DbVisibility(record.visibility.value)
    if is_new or _should_apply_task_field(changed_fields, "workspace_id"):
        task.workspace_id = record.workspace_id
    if is_new or _should_apply_task_field(changed_fields, "created_by_user_id"):
        task.created_by_user_id = record.created_by_user_id
    if is_new or _should_apply_task_field(changed_fields, "title"):
        task.title = record.title
    if is_new or _should_apply_task_field(changed_fields, "note"):
        task.note = record.note
    if is_new or _should_apply_task_field(changed_fields, "category"):
        task.category = record.category
    if is_new or _should_apply_task_field(changed_fields, "is_completed"):
        task.is_completed = record.is_completed
    if is_new or _should_apply_task_field(changed_fields, "shared_completion_mode"):
        task.shared_completion_mode = record.shared_completion_mode.value
    if is_new or _should_apply_task_field(changed_fields, "completed_by_user_ids"):
        task.completed_by_user_ids = _record_completed_by_user_ids(record)
    if is_new or _should_apply_task_field(changed_fields, "due_at"):
        task.due_at = record.due_at
    if is_new or _should_apply_task_field(changed_fields, "reminder_option"):
        task.reminder_option = record.reminder_option
    if is_new or _should_apply_task_field(changed_fields, "reminder_value"):
        task.reminder_value = record.reminder_value
    if is_new:
        task.created_at = record.created_at
    if is_new or _should_apply_task_field(changed_fields, "deleted_at"):
        task.deleted_at = server_deleted_at
        task.purge_after = _server_purge_after(record, server_deleted_at)
    task.updated_by_user_id = record.updated_by_user_id
    task.updated_at = accepted_at
    task.version = 1 if is_new else task.version + 1
    task.device_id = record.device_id
    task.server_updated_at = accepted_at


def _should_apply_task_field(
    changed_fields: set[str] | None,
    field_name: str,
) -> bool:
    return changed_fields is None or field_name in changed_fields


def _completed_by_user_ids(task: Task) -> list[str]:
    return [str(user_id) for user_id in task.completed_by_user_ids or []]


def _record_completed_by_user_ids(record: TaskRecord) -> list[str]:
    return [str(user_id) for user_id in record.completed_by_user_ids]


def _server_deleted_at(
    record: TaskRecord,
    deleted_at: datetime | None,
    accepted_at: datetime,
) -> datetime | None:
    if deleted_at is None:
        return None
    return accepted_at


def _server_purge_after(
    record: TaskRecord,
    server_deleted_at: datetime | None,
) -> datetime | None:
    if server_deleted_at is None or record.deleted_at is None:
        return None
    if record.purge_after is None:
        return None
    return server_deleted_at + (record.purge_after - record.deleted_at)


def _task_subtasks(db: Session, task: Task) -> list[Subtask]:
    return list(
        db.scalars(select(Subtask).where(Subtask.task_sync_id == task.sync_id)).all()
    )


def _validate_record_access(
    db: Session,
    current_user: CurrentUser,
    record: TaskRecord,
    *,
    enforce_record_device: bool = True,
) -> None:
    current_user_id = current_user.user_id
    if (
        enforce_record_device
        and current_user.device_id is not None
        and record.device_id != current_user.device_id
    ):
        raise ValueError(f"Task {record.id} device_id must match the caller device")

    if record.visibility == Visibility.private:
        if record.owner_user_id != current_user_id:
            raise ValueError(f"Private task {record.id} must belong to the caller")
        if record.workspace_id is not None:
            raise ValueError(f"Private task {record.id} cannot have a workspace")
        return

    if record.workspace_id is None:
        raise ValueError(f"Shared task {record.id} must have a workspace")

    membership = db.scalar(
        select(WorkspaceMember).where(
            WorkspaceMember.workspace_id == record.workspace_id,
            WorkspaceMember.user_id == current_user_id,
        )
    )
    if membership is None:
        raise ValueError(f"Shared task {record.id} is not visible to the caller")


def _task_visible_to_user(db: Session, task: Task, user_id: UUID) -> bool:
    if task.visibility == DbVisibility.private:
        return task.owner_user_id == user_id

    membership = db.scalar(
        select(WorkspaceMember).where(
            WorkspaceMember.workspace_id == task.workspace_id,
            WorkspaceMember.user_id == user_id,
        )
    )
    return membership is not None


def _visible_user_ids(db: Session, record: TaskRecord) -> list[UUID]:
    if record.visibility == Visibility.private:
        return [record.owner_user_id]

    user_ids = db.scalars(
        select(WorkspaceMember.user_id).where(
            WorkspaceMember.workspace_id == record.workspace_id
        )
    ).all()
    visible_user_ids: list[UUID] = []
    seen_user_ids: set[UUID] = set()
    for user_id in user_ids:
        if user_id in seen_user_ids:
            continue
        user = db.get(User, user_id)
        if user is None or not user.is_active:
            continue
        seen_user_ids.add(user_id)
        visible_user_ids.append(user_id)
    return visible_user_ids
