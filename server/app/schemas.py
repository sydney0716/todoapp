from datetime import datetime
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, Field


class HealthResponse(BaseModel):
    status: str


class Visibility(StrEnum):
    private = "private"
    shared = "shared"


class SharedCompletionMode(StrEnum):
    single = "single"
    both = "both"


class SyncOperation(StrEnum):
    upsert = "upsert"
    delete = "delete"
    purge = "purge"


class AuthLoginRequest(BaseModel):
    username: str
    password: str
    device_id: UUID
    device_name: str
    platform: str


class AuthResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user_id: UUID
    device_id: UUID


class RefreshRequest(BaseModel):
    refresh_token: str
    device_id: UUID


class SubtaskRecord(BaseModel):
    id: UUID
    task_id: UUID
    title: str
    is_completed: bool = False
    due_at: datetime | None = None
    position: int = 0
    updated_at: datetime
    version: int = Field(ge=1)
    deleted_at: datetime | None = None


class TaskRecord(BaseModel):
    id: UUID
    owner_user_id: UUID
    visibility: Visibility
    workspace_id: UUID | None = None
    title: str
    note: str = ""
    category: str = ""
    is_completed: bool = False
    shared_completion_mode: SharedCompletionMode = SharedCompletionMode.single
    completed_by_user_ids: list[UUID] = Field(default_factory=list)
    due_at: datetime | None = None
    reminder_option: str = "none"
    reminder_value: int | None = None
    created_at: datetime
    updated_at: datetime
    version: int = Field(ge=1)
    deleted_at: datetime | None = None
    purge_after: datetime | None = None
    created_by_user_id: UUID
    updated_by_user_id: UUID
    device_id: UUID
    subtasks: list[SubtaskRecord] = Field(default_factory=list)


class TaskChange(BaseModel):
    operation: SyncOperation
    record: TaskRecord
    event_id: int | None = None
    origin_device_id: UUID | None = None
    changed_task_fields: list[str] | None = None
    changed_subtask_ids: list[UUID] | None = None


class SyncBootstrapResponse(BaseModel):
    cursor: str
    tasks: list[TaskRecord] = Field(default_factory=list)


class SyncPullResponse(BaseModel):
    cursor: str
    changes: list[TaskChange] = Field(default_factory=list)


class SyncPushRequest(BaseModel):
    device_id: UUID
    changes: list[TaskChange] = Field(default_factory=list)


class SyncPushResponse(BaseModel):
    cursor: str
    accepted: list[TaskRecord] = Field(default_factory=list)
    rejected: list[str] = Field(default_factory=list)
