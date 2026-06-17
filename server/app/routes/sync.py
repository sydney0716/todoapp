from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import Session, selectinload

from ..config import get_settings
from ..database import get_db
from ..fixed_accounts import ensure_fixed_accounts
from ..models import (
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
    ensure_fixed_accounts(db, get_settings())
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
    ).all()

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

    ensure_fixed_accounts(db, get_settings())
    accepted: list[TaskRecord] = []
    rejected: list[str] = []

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
        except ValueError as error:
            rejected.append(str(error))
            continue

        accepted.append(record)

    db.commit()
    return SyncPushResponse(
        cursor=_current_cursor(db),
        accepted=accepted,
        rejected=rejected,
    )


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
                updated_at=subtask.updated_at,
                version=subtask.version,
                deleted_at=subtask.deleted_at,
            )
            for subtask in sorted(task_subtasks, key=lambda item: item.position)
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

    existing = db.get(Task, record.id)
    if existing is not None and not _task_visible_to_user(
        db, existing, current_user.user_id
    ):
        raise ValueError(f"Task {record.id} is not visible to the caller")
    if change.operation == SyncOperation.purge:
        task = db.get(Task, record.id)
        if task is not None:
            if task.owner_user_id != current_user.user_id:
                raise ValueError(f"Task {record.id} cannot be purged by this user")
            db.delete(task)
        return record, [], []

    deleted_at = record.deleted_at
    changed_task_fields = _normalized_changed_task_fields(
        existing,
        record,
        deleted_at=deleted_at,
        requested_fields=change.changed_task_fields,
    )
    changed_task_field_set = set(changed_task_fields)
    changed_subtask_ids = [subtask.id for subtask in record.subtasks]
    task = existing
    if task is None:
        task = Task(sync_id=record.id)
        db.add(task)
    task_fields_changed = existing is None or _task_fields_changed(
        existing,
        record,
        deleted_at=deleted_at,
        changed_fields=changed_task_field_set,
    )
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
    for subtask_record in record.subtasks:
        subtask = existing_subtasks.get(subtask_record.id)
        if subtask is None:
            subtask = Subtask(
                sync_id=subtask_record.id,
                task_sync_id=record.id,
                created_at=accepted_at,
            )
            db.add(subtask)
        elif not _subtask_fields_changed(subtask, subtask_record):
            continue

        subtask.task_sync_id = record.id
        subtask.title = subtask_record.title
        subtask.is_completed = subtask_record.is_completed
        subtask.due_at = subtask_record.due_at
        subtask.position = subtask_record.position
        subtask.updated_at = accepted_at
        subtask.version = 1 if subtask.version is None else subtask.version + 1
        subtask.deleted_at = (
            accepted_at if subtask_record.deleted_at is not None else None
        )
        subtask.server_updated_at = accepted_at

    db.flush()
    return (
        _task_to_record(task, subtasks=_task_subtasks(db, task)),
        changed_task_fields,
        changed_subtask_ids,
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
        return [field for field in requested_fields if field in _TASK_FIELD_NAMES]

    changed_fields: list[str] = []
    for field_name in _TASK_FIELD_NAMES:
        if _task_field_changed(existing, record, field_name, deleted_at=deleted_at):
            changed_fields.append(field_name)
    return changed_fields


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


def _task_fields_changed(
    task: Task,
    record: TaskRecord,
    *,
    deleted_at: datetime | None,
    changed_fields: set[str] | None,
) -> bool:
    return (
        (
            _should_apply_task_field(changed_fields, "owner_user_id")
            and task.owner_user_id != record.owner_user_id
        )
        or (
            _should_apply_task_field(changed_fields, "visibility")
            and task.visibility != DbVisibility(record.visibility.value)
        )
        or (
            _should_apply_task_field(changed_fields, "workspace_id")
            and task.workspace_id != record.workspace_id
        )
        or (
            _should_apply_task_field(changed_fields, "created_by_user_id")
            and task.created_by_user_id != record.created_by_user_id
        )
        or (
            _should_apply_task_field(changed_fields, "title")
            and task.title != record.title
        )
        or (
            _should_apply_task_field(changed_fields, "note")
            and task.note != record.note
        )
        or (
            _should_apply_task_field(changed_fields, "category")
            and task.category != record.category
        )
        or (
            _should_apply_task_field(changed_fields, "is_completed")
            and task.is_completed != record.is_completed
        )
        or (
            _should_apply_task_field(changed_fields, "shared_completion_mode")
            and task.shared_completion_mode != record.shared_completion_mode.value
        )
        or (
            _should_apply_task_field(changed_fields, "completed_by_user_ids")
            and _completed_by_user_ids(task) != _record_completed_by_user_ids(record)
        )
        or (
            _should_apply_task_field(changed_fields, "due_at")
            and task.due_at != record.due_at
        )
        or (
            _should_apply_task_field(changed_fields, "reminder_option")
            and task.reminder_option != record.reminder_option
        )
        or (
            _should_apply_task_field(changed_fields, "reminder_value")
            and task.reminder_value != record.reminder_value
        )
        or (
            _should_apply_task_field(changed_fields, "deleted_at")
            and (task.deleted_at is None) != (deleted_at is None)
        )
    )


def _subtask_fields_changed(subtask: Subtask, record: SubtaskRecord) -> bool:
    return (
        subtask.title != record.title
        or subtask.is_completed != record.is_completed
        or subtask.due_at != record.due_at
        or subtask.position != record.position
        or (subtask.deleted_at is None) != (record.deleted_at is None)
    )


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
