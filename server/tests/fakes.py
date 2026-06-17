from __future__ import annotations

import copy
from collections.abc import Iterator
from typing import Any
from uuid import UUID

from sqlalchemy.sql import operators
from sqlalchemy.sql.elements import BinaryExpression

from app.models import (
    Device,
    Subtask,
    SyncEvent,
    Task,
    User,
    Workspace,
    WorkspaceMember,
)
from app.models import (
    Visibility as DbVisibility,
)


class ScalarResult:
    def __init__(self, rows: list[Any]) -> None:
        self._rows = rows

    def __iter__(self) -> Iterator[Any]:
        return iter(self._rows)

    def all(self) -> list[Any]:
        return self._rows


class FakeSession:
    def __init__(self) -> None:
        self.users: dict[UUID, User] = {}
        self.workspaces: dict[UUID, Workspace] = {}
        self.workspace_members: dict[tuple[UUID, UUID], WorkspaceMember] = {}
        self.devices: dict[UUID, Device] = {}
        self.tasks: dict[UUID, Task] = {}
        self.subtasks: dict[UUID, Subtask] = {}
        self.events: list[SyncEvent] = []
        self.next_event_id = 1
        self.commit_count = 0

    def get(self, model: type[Any], key: Any) -> Any | None:
        if model is User:
            return self.users.get(key)
        if model is Workspace:
            return self.workspaces.get(key)
        if model is Device:
            return self.devices.get(key)
        if model is Task:
            return self.tasks.get(key)
        if model is Subtask:
            return self.subtasks.get(key)
        return None

    def add(self, obj: Any) -> None:
        if isinstance(obj, User):
            self.users[obj.id] = obj
        elif isinstance(obj, Workspace):
            self.workspaces[obj.id] = obj
        elif isinstance(obj, WorkspaceMember):
            self.workspace_members[(obj.workspace_id, obj.user_id)] = obj
        elif isinstance(obj, Device):
            self.devices[obj.id] = obj
        elif isinstance(obj, Task):
            self.tasks[obj.sync_id] = obj
        elif isinstance(obj, Subtask):
            self.subtasks[obj.sync_id] = obj
        elif isinstance(obj, SyncEvent):
            obj.id = self.next_event_id
            self.next_event_id += 1
            self.events.append(obj)
        else:
            raise AssertionError(f"Unexpected object added to fake DB: {obj!r}")

    def delete(self, obj: Any) -> None:
        if isinstance(obj, Device):
            self.devices.pop(obj.id, None)
        elif isinstance(obj, Task):
            self.tasks.pop(obj.sync_id, None)
            for subtask_id, subtask in list(self.subtasks.items()):
                if subtask.task_sync_id == obj.sync_id:
                    self.subtasks.pop(subtask_id, None)
        elif isinstance(obj, Subtask):
            self.subtasks.pop(obj.sync_id, None)
        else:
            raise AssertionError(f"Unexpected object deleted from fake DB: {obj!r}")

    def scalar(self, statement: Any) -> Any | None:
        entity = _selected_entity(statement)
        filters = _filters(statement)
        if entity is User:
            username = filters["eq"].get("username")
            return next(
                (user for user in self.users.values() if user.username == username),
                None,
            )
        if entity is WorkspaceMember:
            workspace_id = filters["eq"].get("workspace_id")
            user_id = filters["eq"].get("user_id")
            return self.workspace_members.get((workspace_id, user_id))
        if entity is None or entity is SyncEvent:
            return max((event.id for event in self.events), default=0)
        raise AssertionError(f"Unexpected scalar query entity: {entity!r}")

    def scalars(self, statement: Any) -> ScalarResult:
        entity = _selected_entity(statement)
        filters = _filters(statement)
        if entity is Task:
            user_id = filters["eq"].get("owner_user_id")
            tasks = [
                task
                for task in self.tasks.values()
                if user_id is None or self._task_visible_to_user(task, user_id)
            ]
            for task in tasks:
                task.subtasks = [
                    subtask
                    for subtask in self.subtasks.values()
                    if subtask.task_sync_id == task.sync_id
                ]
            tasks.sort(key=lambda task: (task.updated_at, task.sync_id))
            return ScalarResult(tasks)
        if entity is SyncEvent:
            visible_user_id = filters["eq"].get("visible_user_id")
            cursor_id = filters["gt"].get("id", 0)
            events = [
                event
                for event in self.events
                if event.visible_user_id == visible_user_id and event.id > cursor_id
            ]
            events.sort(key=lambda event: event.id)
            return ScalarResult(events)
        if entity is Subtask:
            task_sync_id = filters["eq"].get("task_sync_id")
            return ScalarResult(
                [
                    subtask
                    for subtask in self.subtasks.values()
                    if subtask.task_sync_id == task_sync_id
                ]
            )
        if entity is WorkspaceMember:
            workspace_id = filters["eq"].get("workspace_id")
            return ScalarResult(
                [
                    member.user_id
                    for member in self.workspace_members.values()
                    if member.workspace_id == workspace_id
                ]
            )
        raise AssertionError(f"Unexpected scalars query entity: {entity!r}")

    def begin_nested(self) -> FakeNestedTransaction:
        return FakeNestedTransaction(self)

    def flush(self) -> None:
        return None

    def commit(self) -> None:
        self.commit_count += 1

    def close(self) -> None:
        return None

    def _snapshot(self) -> dict[str, Any]:
        return {
            "users": copy.deepcopy(self.users),
            "workspaces": copy.deepcopy(self.workspaces),
            "workspace_members": copy.deepcopy(self.workspace_members),
            "devices": copy.deepcopy(self.devices),
            "tasks": copy.deepcopy(self.tasks),
            "subtasks": copy.deepcopy(self.subtasks),
            "events": copy.deepcopy(self.events),
            "next_event_id": self.next_event_id,
            "commit_count": self.commit_count,
        }

    def _restore(self, snapshot: dict[str, Any]) -> None:
        self.users = snapshot["users"]
        self.workspaces = snapshot["workspaces"]
        self.workspace_members = snapshot["workspace_members"]
        self.devices = snapshot["devices"]
        self.tasks = snapshot["tasks"]
        self.subtasks = snapshot["subtasks"]
        self.events = snapshot["events"]
        self.next_event_id = snapshot["next_event_id"]
        self.commit_count = snapshot["commit_count"]

    def _task_visible_to_user(self, task: Task, user_id: UUID) -> bool:
        if task.visibility == DbVisibility.private:
            return task.owner_user_id == user_id
        return (task.workspace_id, user_id) in self.workspace_members


class FakeNestedTransaction:
    def __init__(self, db: FakeSession) -> None:
        self.db = db
        self.snapshot: dict[str, Any] | None = None

    def __enter__(self) -> FakeNestedTransaction:
        self.snapshot = self.db._snapshot()
        return self

    def __exit__(self, exc_type: type[BaseException] | None, *_: Any) -> bool:
        if exc_type is not None and self.snapshot is not None:
            self.db._restore(self.snapshot)
        return False


def _selected_entity(statement: Any) -> type[Any] | None:
    descriptions = getattr(statement, "column_descriptions", [])
    if not descriptions:
        return None
    return descriptions[0].get("entity")


def _filters(statement: Any) -> dict[str, dict[str, Any]]:
    filters: dict[str, dict[str, Any]] = {"eq": {}, "gt": {}}
    _collect_filters(getattr(statement, "whereclause", None), filters)
    return filters


def _collect_filters(expression: Any, filters: dict[str, dict[str, Any]]) -> None:
    if expression is None:
        return
    if isinstance(expression, BinaryExpression):
        key = getattr(expression.left, "key", None)
        value = getattr(expression.right, "value", None)
        if key is not None and expression.operator is operators.eq:
            filters["eq"][key] = value
        elif key is not None and expression.operator is operators.gt:
            filters["gt"][key] = value
        return
    for child in expression.get_children():
        _collect_filters(child, filters)
