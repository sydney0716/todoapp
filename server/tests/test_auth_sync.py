from __future__ import annotations

from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

import pytest
from fakes import FakeSession
from fastapi.testclient import TestClient

from app.config import get_settings
from app.database import get_db
from app.fixed_accounts import (
    DEFAULT_CURRENT_USER_ID,
    DEFAULT_SHARED_WORKSPACE_ID,
    PARTNER_USER_ID,
)
from app.main import app
from app.models import (
    Subtask,
    SyncEvent,
    Task,
    WorkspaceMember,
)
from app.models import (
    Visibility as DbVisibility,
)
from app.security import verify_token

DEVICE_ID = UUID("10000000-0000-4000-8000-000000000001")
OTHER_DEVICE_ID = UUID("10000000-0000-4000-8000-000000000002")
TASK_ID = UUID("20000000-0000-4000-8000-000000000001")
SUBTASK_ID = UUID("30000000-0000-4000-8000-000000000001")
SUBTASK_TWO_ID = UUID("30000000-0000-4000-8000-000000000002")


@pytest.fixture(autouse=True)
def test_settings(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    monkeypatch.setenv("JWT_SECRET", "test-jwt-secret")
    monkeypatch.setenv("ACCESS_TOKEN_MINUTES", "15")
    monkeypatch.setenv("REFRESH_TOKEN_DAYS", "60")
    monkeypatch.setenv("USER1_PASSWORD", "user1-test-password")
    monkeypatch.setenv("USER2_PASSWORD", "user2-test-password")
    get_settings.cache_clear()
    yield
    app.dependency_overrides.clear()
    get_settings.cache_clear()


@pytest.fixture
def fake_db() -> FakeSession:
    return FakeSession()


@pytest.fixture
def client(fake_db: FakeSession) -> Iterator[TestClient]:
    def override_db() -> Iterator[FakeSession]:
        yield fake_db

    app.dependency_overrides[get_db] = override_db
    with TestClient(app) as test_client:
        yield test_client


def test_sync_event_operation_uses_existing_database_enum() -> None:
    operation_type = SyncEvent.__table__.c.operation.type

    assert operation_type.name == "sync_operation"


def test_login_seeds_fixed_accounts_and_device(
    client: TestClient, fake_db: FakeSession
) -> None:
    auth = _login(client)

    assert auth["user_id"] == str(DEFAULT_CURRENT_USER_ID)
    assert DEFAULT_CURRENT_USER_ID in fake_db.users
    assert PARTNER_USER_ID in fake_db.users
    assert DEFAULT_SHARED_WORKSPACE_ID in fake_db.workspaces
    assert (DEFAULT_SHARED_WORKSPACE_ID, DEFAULT_CURRENT_USER_ID) in (
        fake_db.workspace_members
    )
    assert (DEFAULT_SHARED_WORKSPACE_ID, PARTNER_USER_ID) in fake_db.workspace_members

    device = fake_db.devices[DEVICE_ID]
    assert device.user_id == DEFAULT_CURRENT_USER_ID
    assert device.refresh_token_hash != auth["refresh_token"]
    assert verify_token(auth["refresh_token"], device.refresh_token_hash)
    assert device.refresh_token_expires_at > datetime.now(UTC) + timedelta(days=59)


def test_refresh_keeps_refresh_token_valid_for_device(
    client: TestClient,
) -> None:
    auth = _login(client)

    refresh_response = client.post(
        "/auth/refresh",
        json={"refresh_token": auth["refresh_token"], "device_id": auth["device_id"]},
    )

    assert refresh_response.status_code == 200
    refreshed_auth = refresh_response.json()
    assert refreshed_auth["refresh_token"] == auth["refresh_token"]

    second_refresh_response = client.post(
        "/auth/refresh",
        json={"refresh_token": auth["refresh_token"], "device_id": auth["device_id"]},
    )

    assert second_refresh_response.status_code == 200


def test_logout_invalidates_refresh_token_without_deleting_device(
    client: TestClient,
    fake_db: FakeSession,
) -> None:
    auth = _login(client)

    logout_response = client.post(
        "/auth/logout",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
    )

    assert logout_response.status_code == 204
    assert DEVICE_ID in fake_db.devices

    refresh_response = client.post(
        "/auth/refresh",
        json={"refresh_token": auth["refresh_token"], "device_id": auth["device_id"]},
    )

    assert refresh_response.status_code == 401


def test_authenticated_bootstrap_returns_visible_tasks(
    client: TestClient, fake_db: FakeSession
) -> None:
    auth = _login(client)
    task = _task()
    fake_db.add(task)

    response = client.get(
        "/sync/bootstrap",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["cursor"] == "0"
    assert [record["id"] for record in payload["tasks"]] == [str(TASK_ID)]


def test_task_push_then_pull_round_trip(client: TestClient) -> None:
    auth = _login(client)
    record = _task_record()

    push_response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [{"operation": "upsert", "record": record}],
        },
    )

    assert push_response.status_code == 200
    push_payload = push_response.json()
    assert push_payload["cursor"] == "1"
    assert push_payload["rejected"] == []
    assert [record["id"] for record in push_payload["accepted"]] == [str(TASK_ID)]
    assert _parse_json_datetime(push_payload["accepted"][0]["updated_at"]) == (
        _parse_json_datetime(record["updated_at"])
    )

    pull_response = client.get(
        "/sync/tasks",
        params={"cursor": "0"},
        headers={"Authorization": f"Bearer {auth['access_token']}"},
    )

    assert pull_response.status_code == 200
    pull_payload = pull_response.json()
    assert pull_payload["cursor"] == "1"
    assert pull_payload["changes"] == []

    other_auth = _login(client, OTHER_DEVICE_ID)
    other_pull_response = client.get(
        "/sync/tasks",
        params={"cursor": "0"},
        headers={"Authorization": f"Bearer {other_auth['access_token']}"},
    )

    assert other_pull_response.status_code == 200
    other_pull_payload = other_pull_response.json()
    assert other_pull_payload["cursor"] == "1"
    assert len(other_pull_payload["changes"]) == 1
    assert other_pull_payload["changes"][0]["operation"] == "upsert"
    assert other_pull_payload["changes"][0]["record"]["id"] == str(TASK_ID)
    assert other_pull_payload["changes"][0]["event_id"] == 1
    assert other_pull_payload["changes"][0]["origin_device_id"] == auth["device_id"]
    assert "title" in other_pull_payload["changes"][0]["changed_task_fields"]
    assert other_pull_payload["changes"][0]["changed_subtask_ids"] == []


def test_shared_both_completion_round_trips_to_partner(client: TestClient) -> None:
    auth = _login(client)
    record = _task_record(
        visibility="shared",
        workspace_id=DEFAULT_SHARED_WORKSPACE_ID,
        shared_completion_mode="both",
        completed_by_user_ids=[DEFAULT_CURRENT_USER_ID],
    )

    push_response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [{"operation": "upsert", "record": record}],
        },
    )

    assert push_response.status_code == 200
    push_payload = push_response.json()
    assert push_payload["rejected"] == []
    accepted_record = push_payload["accepted"][0]
    assert accepted_record["shared_completion_mode"] == "both"
    assert accepted_record["completed_by_user_ids"] == [str(DEFAULT_CURRENT_USER_ID)]
    assert accepted_record["is_completed"] is False

    partner_auth = _login(client, OTHER_DEVICE_ID, username="user2")
    pull_response = client.get(
        "/sync/tasks",
        params={"cursor": "0"},
        headers={"Authorization": f"Bearer {partner_auth['access_token']}"},
    )

    assert pull_response.status_code == 200
    change_record = pull_response.json()["changes"][0]["record"]
    assert change_record["shared_completion_mode"] == "both"
    assert change_record["completed_by_user_ids"] == [str(DEFAULT_CURRENT_USER_ID)]
    assert change_record["is_completed"] is False


def test_shared_push_ignores_stale_workspace_members(
    client: TestClient, fake_db: FakeSession
) -> None:
    auth = _login(client)
    fake_db.add(
        WorkspaceMember(
            workspace_id=DEFAULT_SHARED_WORKSPACE_ID,
            user_id=UUID("00000000-0000-4000-8000-000000000999"),
        )
    )
    record = _task_record(
        visibility="shared",
        workspace_id=DEFAULT_SHARED_WORKSPACE_ID,
    )

    response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [{"operation": "upsert", "record": record}],
        },
    )

    assert response.status_code == 200
    assert response.json()["rejected"] == []
    assert {event.visible_user_id for event in fake_db.events} == {
        DEFAULT_CURRENT_USER_ID,
        PARTNER_USER_ID,
    }


def test_push_stores_sync_event_metadata(
    client: TestClient, fake_db: FakeSession
) -> None:
    auth = _login(client)
    fake_db.add(_task(version=1))
    fake_db.add(_subtask(title="Produce", version=1))
    record = _task_record(version=2)
    record["subtasks"] = [
        _subtask_record(title="Produce", is_completed=True, version=2)
    ]

    response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [
                {
                    "operation": "upsert",
                    "record": record,
                    "changed_task_fields": [],
                }
            ],
        },
    )

    assert response.status_code == 200
    assert response.json()["rejected"] == []
    assert fake_db.events[0].origin_device_id == DEVICE_ID
    assert fake_db.events[0].changed_task_fields == []
    assert fake_db.events[0].changed_subtask_ids == [str(SUBTASK_ID)]


def test_noop_upsert_is_accepted_without_sync_event(
    client: TestClient, fake_db: FakeSession
) -> None:
    auth = _login(client)
    fake_db.add(_task(title="Server task", version=1))
    record = _task_record(title="Server task", version=1)

    response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [
                {
                    "operation": "upsert",
                    "record": record,
                    "changed_task_fields": [],
                }
            ],
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["cursor"] == "0"
    assert payload["rejected"] == []
    assert payload["accepted"][0]["id"] == str(TASK_ID)
    assert fake_db.tasks[TASK_ID].version == 1
    assert fake_db.events == []


def test_stale_subtask_change_keeps_server_subtask(
    client: TestClient, fake_db: FakeSession
) -> None:
    auth = _login(client)
    existing_task = _task(title="Original title", version=2)
    existing_subtask = _subtask(version=2)
    fake_db.add(existing_task)
    fake_db.add(existing_subtask)

    pushed_record = _task_record(title="Accepted title", version=3)
    pushed_record["subtasks"] = [
        _subtask_record(title="Accepted subtask title", version=1)
    ]
    response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [{"operation": "upsert", "record": pushed_record}],
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["rejected"] == []
    assert fake_db.tasks[TASK_ID].title == "Accepted title"
    assert fake_db.tasks[TASK_ID].version == 3
    assert fake_db.subtasks[SUBTASK_ID].title == "Existing subtask"
    assert fake_db.subtasks[SUBTASK_ID].version == 2
    assert len(fake_db.events) == 1


def test_subtask_due_at_round_trips_through_push(
    client: TestClient, fake_db: FakeSession
) -> None:
    auth = _login(client)
    due_at = "2026-06-10T00:00:00+00:00"
    fake_db.add(_task(version=1))
    fake_db.add(_subtask(version=1))
    pushed_record = _task_record(version=2)
    pushed_record["subtasks"] = [
        _subtask_record(
            title="Existing subtask",
            due_at=due_at,
            version=2,
        )
    ]

    response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [
                {
                    "operation": "upsert",
                    "record": pushed_record,
                    "changed_task_fields": [],
                }
            ],
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["rejected"] == []
    accepted_due_at = payload["accepted"][0]["subtasks"][0]["due_at"]
    assert datetime.fromisoformat(accepted_due_at.replace("Z", "+00:00")) == (
        datetime.fromisoformat(due_at)
    )
    assert fake_db.subtasks[SUBTASK_ID].due_at == datetime(
        2026, 6, 10, tzinfo=UTC
    )
    assert fake_db.events[0].changed_subtask_ids == [str(SUBTASK_ID)]


def test_subtask_changes_merge_by_subtask_id(
    client: TestClient, fake_db: FakeSession
) -> None:
    auth_a = _login(client)
    auth_b = _login(client, OTHER_DEVICE_ID)
    fake_db.add(_task(version=1))
    fake_db.add(_subtask(title="Produce", version=1))
    fake_db.add(_subtask(id=SUBTASK_TWO_ID, title="Milk", version=1))

    first_record = _task_record(version=2)
    first_record["subtasks"] = [
        _subtask_record(title="Produce", is_completed=True, version=2)
    ]
    first_response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth_a['access_token']}"},
        json={
            "device_id": auth_a["device_id"],
            "changes": [
                {
                    "operation": "upsert",
                    "record": first_record,
                    "changed_task_fields": [],
                }
            ],
        },
    )
    assert first_response.status_code == 200
    assert first_response.json()["rejected"] == []

    second_record = _task_record(version=2, device_id=OTHER_DEVICE_ID)
    second_record["subtasks"] = [
        _subtask_record(
            id=SUBTASK_TWO_ID,
            title="Milk",
            is_completed=True,
            version=2,
        )
    ]
    second_response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth_b['access_token']}"},
        json={
            "device_id": auth_b["device_id"],
            "changes": [
                {
                    "operation": "upsert",
                    "record": second_record,
                    "changed_task_fields": [],
                }
            ],
        },
    )

    assert second_response.status_code == 200
    payload = second_response.json()
    assert payload["rejected"] == []
    merged_subtasks = {
        record["id"]: record["is_completed"]
        for record in payload["accepted"][0]["subtasks"]
    }
    assert merged_subtasks[str(SUBTASK_ID)] is True
    assert merged_subtasks[str(SUBTASK_TWO_ID)] is True
    assert fake_db.subtasks[SUBTASK_ID].is_completed is True
    assert fake_db.subtasks[SUBTASK_TWO_ID].is_completed is True
    assert fake_db.tasks[TASK_ID].version == 1
    assert fake_db.events[0].changed_task_fields == []
    assert fake_db.events[0].changed_subtask_ids == [str(SUBTASK_ID)]
    assert fake_db.events[1].changed_task_fields == []
    assert fake_db.events[1].changed_subtask_ids == [str(SUBTASK_TWO_ID)]


def test_subtask_change_ignores_stale_parent_fields(
    client: TestClient, fake_db: FakeSession
) -> None:
    auth = _login(client)
    fake_db.add(_task(title="Renamed on other device", version=2))
    fake_db.add(_subtask(title="Produce", version=1))

    stale_parent_record = _task_record(title="Server task", version=1)
    stale_parent_record["subtasks"] = [
        _subtask_record(title="Produce", is_completed=True, version=2)
    ]
    response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [
                {
                    "operation": "upsert",
                    "record": stale_parent_record,
                    "changed_task_fields": [],
                }
            ],
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["rejected"] == []
    assert payload["accepted"][0]["title"] == "Renamed on other device"
    assert fake_db.tasks[TASK_ID].title == "Renamed on other device"
    assert fake_db.tasks[TASK_ID].version == 2
    assert fake_db.subtasks[SUBTASK_ID].is_completed is True


def test_parent_only_change_does_not_apply_stale_subtask_snapshot(
    client: TestClient,
    fake_db: FakeSession,
) -> None:
    auth = _login(client)
    fake_db.add(_task(title="Server task", version=1))
    fake_db.add(_subtask(title="Accepted subtask title", version=2))

    record = _task_record(title="Renamed task", version=2)
    record["updated_at"] = "2026-01-01T12:05:00+00:00"
    record["subtasks"] = [
        _subtask_record(title="Stale subtask title", version=1),
    ]

    response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [
                {
                    "operation": "upsert",
                    "record": record,
                    "changed_task_fields": ["title"],
                    "changed_subtask_ids": [],
                }
            ],
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["rejected"] == []
    assert payload["accepted"][0]["title"] == "Renamed task"
    assert fake_db.tasks[TASK_ID].title == "Renamed task"
    assert fake_db.subtasks[SUBTASK_ID].title == "Accepted subtask title"
    assert fake_db.events[0].changed_task_fields == ["title"]
    assert fake_db.events[0].changed_subtask_ids == []


def test_task_change_after_subtask_change_is_accepted(
    client: TestClient, fake_db: FakeSession
) -> None:
    auth = _login(client)
    fake_db.add(_task(title="Server task", version=1))
    fake_db.add(_subtask(title="Produce", is_completed=True, version=2))

    record = _task_record(title="Renamed task", version=2)
    response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [
                {
                    "operation": "upsert",
                    "record": record,
                    "changed_task_fields": ["title"],
                }
            ],
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["rejected"] == []
    assert payload["accepted"][0]["title"] == "Renamed task"
    assert fake_db.tasks[TASK_ID].title == "Renamed task"
    assert fake_db.tasks[TASK_ID].version == 2
    assert fake_db.subtasks[SUBTASK_ID].is_completed is True


def test_same_version_task_change_is_accepted(
    client: TestClient, fake_db: FakeSession
) -> None:
    auth = _login(client)
    fake_db.add(_task(title="Older task title", version=2))

    record = _task_record(title="Newer task title", version=2)
    record["updated_at"] = "2026-01-01T12:05:00+00:00"
    response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [
                {
                    "operation": "upsert",
                    "record": record,
                    "changed_task_fields": ["title"],
                }
            ],
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["rejected"] == []
    assert payload["accepted"][0]["title"] == "Newer task title"
    assert fake_db.tasks[TASK_ID].title == "Newer task title"
    assert fake_db.tasks[TASK_ID].version == 2
    assert fake_db.events[0].changed_task_fields == ["title"]


def test_stale_same_field_task_change_is_accepted_without_event(
    client: TestClient,
    fake_db: FakeSession,
) -> None:
    auth = _login(client)
    fake_db.add(
        _task(
            title="Server canonical title",
            version=2,
            updated_at=datetime(2026, 1, 1, 12, 5, tzinfo=UTC),
        )
    )

    record = _task_record(title="Older task title", version=2)
    response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [
                {
                    "operation": "upsert",
                    "record": record,
                    "changed_task_fields": ["title"],
                }
            ],
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["cursor"] == "0"
    assert payload["rejected"] == []
    assert payload["accepted"][0]["title"] == "Server canonical title"
    assert fake_db.tasks[TASK_ID].title == "Server canonical title"
    assert fake_db.events == []


def test_same_field_concurrent_edits_latest_accepted_is_canonical(
    client: TestClient, fake_db: FakeSession
) -> None:
    auth_a = _login(client)
    auth_b = _login(client, OTHER_DEVICE_ID)
    fake_db.add(_task(title="Original task title", version=1))

    first_record = _task_record(title="First accepted title", version=2)
    first_response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth_a['access_token']}"},
        json={
            "device_id": auth_a["device_id"],
            "changes": [
                {
                    "operation": "upsert",
                    "record": first_record,
                    "changed_task_fields": ["title"],
                }
            ],
        },
    )
    assert first_response.status_code == 200
    assert first_response.json()["rejected"] == []

    second_record = _task_record(
        title="Second accepted title",
        version=2,
        device_id=OTHER_DEVICE_ID,
    )
    second_record["updated_at"] = "2026-01-01T12:05:00+00:00"
    second_response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth_b['access_token']}"},
        json={
            "device_id": auth_b["device_id"],
            "changes": [
                {
                    "operation": "upsert",
                    "record": second_record,
                    "changed_task_fields": ["title"],
                }
            ],
        },
    )

    assert second_response.status_code == 200
    assert second_response.json()["rejected"] == []
    assert fake_db.tasks[TASK_ID].title == "Second accepted title"
    assert fake_db.tasks[TASK_ID].version == 2
    assert len(fake_db.events) == 2


def test_shared_to_private_emits_remove_event_for_user_losing_visibility(
    client: TestClient, fake_db: FakeSession
) -> None:
    auth = _login(client)
    shared_task = _task(title="Shared task", version=1)
    shared_task.visibility = DbVisibility.shared
    shared_task.workspace_id = DEFAULT_SHARED_WORKSPACE_ID
    fake_db.add(shared_task)

    record = _task_record(title="Private task", version=2)
    response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [
                {
                    "operation": "upsert",
                    "record": record,
                    "changed_task_fields": ["title", "visibility", "workspace_id"],
                }
            ],
        },
    )

    assert response.status_code == 200
    assert response.json()["rejected"] == []
    assert fake_db.tasks[TASK_ID].visibility == DbVisibility.private
    events_by_user = {event.visible_user_id: event for event in fake_db.events}
    assert events_by_user[DEFAULT_CURRENT_USER_ID].operation.value == "upsert"
    assert events_by_user[PARTNER_USER_ID].operation.value == "purge"

    partner_auth = _login(client, OTHER_DEVICE_ID, username="user2")
    pull_response = client.get(
        "/sync/tasks",
        params={"cursor": "0"},
        headers={"Authorization": f"Bearer {partner_auth['access_token']}"},
    )

    assert pull_response.status_code == 200
    pull_payload = pull_response.json()
    assert pull_payload["cursor"] == "2"
    assert len(pull_payload["changes"]) == 1
    assert pull_payload["changes"][0]["operation"] == "purge"
    assert pull_payload["changes"][0]["record"]["id"] == str(TASK_ID)


def test_stale_shared_push_is_rejected_after_task_becomes_private(
    client: TestClient, fake_db: FakeSession
) -> None:
    auth = _login(client, OTHER_DEVICE_ID, username="user2")
    fake_db.add(_task(title="Private task", version=2))

    stale_shared_record = _task_record(
        title="Stale partner edit",
        version=3,
        device_id=OTHER_DEVICE_ID,
        visibility="shared",
        workspace_id=DEFAULT_SHARED_WORKSPACE_ID,
    )
    response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [
                {
                    "operation": "upsert",
                    "record": stale_shared_record,
                    "changed_task_fields": ["title"],
                }
            ],
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["accepted"] == []
    assert "not visible to the caller" in payload["rejected"][0]
    assert fake_db.tasks[TASK_ID].title == "Private task"


def test_task_record_device_must_match_authenticated_device(
    client: TestClient,
) -> None:
    auth = _login(client)
    record = _task_record(device_id=OTHER_DEVICE_ID)

    response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [{"operation": "upsert", "record": record}],
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["accepted"] == []
    assert "device_id must match" in payload["rejected"][0]


def test_purge_deletes_visible_task_even_if_record_device_differs(
    client: TestClient, fake_db: FakeSession
) -> None:
    auth = _login(client)
    deleted_at = datetime(2026, 1, 1, 12, 0, tzinfo=UTC)
    purge_after = datetime(2026, 1, 1, 12, 0, tzinfo=UTC)
    fake_db.add(
        _task(
            device_id=OTHER_DEVICE_ID,
            deleted_at=deleted_at,
            purge_after=purge_after,
        )
    )
    record = _task_record(
        device_id=OTHER_DEVICE_ID,
        deleted_at=deleted_at,
        purge_after=purge_after,
    )

    response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [{"operation": "purge", "record": record}],
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["rejected"] == []
    assert payload["accepted"][0]["id"] == str(TASK_ID)
    assert TASK_ID not in fake_db.tasks
    assert fake_db.events[0].operation.value == "purge"


def test_purge_rejects_task_that_is_not_in_trash(
    client: TestClient,
    fake_db: FakeSession,
) -> None:
    auth = _login(client)
    fake_db.add(_task())
    record = _task_record()

    response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [{"operation": "purge", "record": record}],
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["accepted"] == []
    assert "cannot be purged before trash" in payload["rejected"][0]
    assert TASK_ID in fake_db.tasks
    assert fake_db.events == []


def test_purge_rejects_trash_before_retention_expires(
    client: TestClient,
    fake_db: FakeSession,
) -> None:
    auth = _login(client)
    deleted_at = datetime(2026, 1, 1, 12, 0, tzinfo=UTC)
    purge_after = datetime.now(UTC) + timedelta(days=30)
    fake_db.add(_task(deleted_at=deleted_at, purge_after=purge_after))
    record = _task_record(deleted_at=deleted_at, purge_after=purge_after)

    response = client.post(
        "/sync/tasks",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
        json={
            "device_id": auth["device_id"],
            "changes": [{"operation": "purge", "record": record}],
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["accepted"] == []
    assert "cannot be purged before retention expires" in payload["rejected"][0]
    assert TASK_ID in fake_db.tasks
    assert fake_db.events == []


def _login(
    client: TestClient,
    device_id: UUID = DEVICE_ID,
    *,
    username: str = "user1",
) -> dict[str, Any]:
    password = (
        "user2-test-password" if username == "user2" else "user1-test-password"
    )
    response = client.post(
        "/auth/login",
        json={
            "username": username,
            "password": password,
            "device_id": str(device_id),
            "device_name": "pytest device",
            "platform": "android",
        },
    )
    assert response.status_code == 200
    return response.json()


def _parse_json_datetime(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def _task(
    *,
    title: str = "Server task",
    version: int = 1,
    device_id: UUID = DEVICE_ID,
    shared_completion_mode: str = "single",
    completed_by_user_ids: list[UUID] | None = None,
    updated_at: datetime | None = None,
    deleted_at: datetime | None = None,
    purge_after: datetime | None = None,
) -> Task:
    now = datetime(2026, 1, 1, 12, 0, tzinfo=UTC)
    task = Task(
        sync_id=TASK_ID,
        owner_user_id=DEFAULT_CURRENT_USER_ID,
        visibility=DbVisibility.private,
        workspace_id=None,
        created_by_user_id=DEFAULT_CURRENT_USER_ID,
        updated_by_user_id=DEFAULT_CURRENT_USER_ID,
        title=title,
        note="",
        category="",
        is_completed=False,
        shared_completion_mode=shared_completion_mode,
        completed_by_user_ids=[str(user_id) for user_id in completed_by_user_ids or []],
        due_at=None,
        reminder_option="none",
        reminder_value=None,
        created_at=now,
        updated_at=updated_at or now,
        version=version,
        deleted_at=deleted_at,
        purge_after=purge_after,
        device_id=device_id,
    )
    task.subtasks = []
    return task


def _subtask(
    *,
    id: UUID = SUBTASK_ID,
    title: str = "Existing subtask",
    is_completed: bool = False,
    due_at: datetime | None = None,
    version: int = 1,
) -> Subtask:
    now = datetime(2026, 1, 1, 12, 0, tzinfo=UTC)
    return Subtask(
        sync_id=id,
        task_sync_id=TASK_ID,
        title=title,
        is_completed=is_completed,
        due_at=due_at,
        position=0,
        created_at=now,
        updated_at=now,
        version=version,
        deleted_at=None,
    )


def _task_record(
    *,
    title: str = "Server task",
    version: int = 1,
    device_id: UUID = DEVICE_ID,
    updated_at: datetime | None = None,
    deleted_at: datetime | None = None,
    purge_after: datetime | None = None,
    visibility: str = "private",
    workspace_id: UUID | None = None,
    is_completed: bool = False,
    shared_completion_mode: str = "single",
    completed_by_user_ids: list[UUID] | None = None,
) -> dict[str, Any]:
    now = "2026-01-01T12:00:00+00:00"
    return {
        "id": str(TASK_ID),
        "owner_user_id": str(DEFAULT_CURRENT_USER_ID),
        "visibility": visibility,
        "workspace_id": str(workspace_id) if workspace_id is not None else None,
        "title": title,
        "note": "",
        "category": "",
        "is_completed": is_completed,
        "shared_completion_mode": shared_completion_mode,
        "completed_by_user_ids": [
            str(user_id) for user_id in completed_by_user_ids or []
        ],
        "due_at": None,
        "reminder_option": "none",
        "reminder_value": None,
        "created_at": now,
        "updated_at": (updated_at.isoformat() if updated_at is not None else now),
        "version": version,
        "deleted_at": deleted_at.isoformat() if deleted_at is not None else None,
        "purge_after": purge_after.isoformat() if purge_after is not None else None,
        "created_by_user_id": str(DEFAULT_CURRENT_USER_ID),
        "updated_by_user_id": str(DEFAULT_CURRENT_USER_ID),
        "device_id": str(device_id),
        "subtasks": [],
    }


def _subtask_record(
    *,
    id: UUID = SUBTASK_ID,
    title: str = "Existing subtask",
    is_completed: bool = False,
    due_at: str | None = None,
    version: int = 1,
) -> dict[str, Any]:
    return {
        "id": str(id),
        "task_id": str(TASK_ID),
        "title": title,
        "is_completed": is_completed,
        "due_at": due_at,
        "position": 0,
        "updated_at": "2026-01-01T12:00:00+00:00",
        "version": version,
        "deleted_at": None,
    }
