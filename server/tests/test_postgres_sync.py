from __future__ import annotations

import os
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from pathlib import Path
from threading import Event
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event, text
from sqlalchemy.orm import Session
from test_auth_sync import (
    DEVICE_ID,
    OTHER_DEVICE_ID,
    SUBTASK_ID,
    TASK_ID,
    _subtask_record,
    _task_record,
)

from app.config import get_settings
from app.database import get_db
from app.fixed_accounts import (
    DEFAULT_CURRENT_USER_ID,
    DEFAULT_SHARED_WORKSPACE_ID,
    PARTNER_USER_ID,
    ensure_fixed_accounts,
)
from app.main import app
from app.models import Device, PurgedTask, Subtask, SyncEvent, Task
from app.models import SyncOperation as DbSyncOperation
from app.routes.sync import bootstrap, pull_tasks, push_tasks
from app.runtime_schema import apply_migrations
from app.schemas import SubtaskRecord, SyncOperation, SyncPushRequest, TaskRecord
from app.security import CurrentUser

DATABASE_URL = os.getenv("TODOAPP_TEST_DATABASE_URL")
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="Needs isolated PostgreSQL")


@pytest.fixture
def database(monkeypatch):
    monkeypatch.setenv("USER1_PASSWORD", "postgres-test-one")
    monkeypatch.setenv("USER2_PASSWORD", "postgres-test-two")
    monkeypatch.setenv("JWT_SECRET", "postgres-integration-test-secret")
    monkeypatch.setenv("AUTO_MIGRATE", "false")
    get_settings.cache_clear()
    admin = create_engine(DATABASE_URL)
    schema = f"todoapp_sync_{uuid4().hex}"
    with admin.begin() as conn:
        conn.exec_driver_sql(f'CREATE SCHEMA "{schema}"')
    engine = create_engine(
        DATABASE_URL, connect_args={"options": f"-csearch_path={schema},public"}
    )
    try:
        with Session(engine) as db:
            apply_migrations(db)
            apply_migrations(db)
            migration_count = len(
                list((Path(__file__).resolve().parents[1] / "migrations").glob("*.sql"))
            )
            assert db.scalar(text("SELECT count(*) FROM schema_migrations")) == (
                migration_count
            )
        with Session(engine) as db:
            ensure_fixed_accounts(db, get_settings())
            for device_id, user_id in (
                (DEVICE_ID, DEFAULT_CURRENT_USER_ID),
                (OTHER_DEVICE_ID, PARTNER_USER_ID),
            ):
                db.add(
                    Device(
                        id=device_id,
                        user_id=user_id,
                        device_name="Test",
                        platform="macos",
                        refresh_token_hash="test",
                        refresh_token_expires_at=datetime.now(UTC) + timedelta(days=1),
                    )
                )
            db.commit()
        yield engine
    finally:
        engine.dispose()
        with admin.begin() as conn:
            conn.exec_driver_sql(f'DROP SCHEMA "{schema}" CASCADE')
        admin.dispose()
        get_settings.cache_clear()


@pytest.fixture
def client(database):
    def override_db():
        with Session(database, autoflush=False, expire_on_commit=False) as db:
            yield db

    app.dependency_overrides[get_db] = override_db
    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        app.dependency_overrides.clear()


def login(client, username, password, device_id, *, platform="macos"):
    response = client.post(
        "/auth/login",
        json={
            "username": username,
            "password": password,
            "device_id": str(device_id),
            "device_name": "Integration test",
            "platform": platform,
        },
    )
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.parametrize(
    ("username", "password", "user_id"),
    [
        ("user1", "postgres-test-one", DEFAULT_CURRENT_USER_ID),
        ("user2", "postgres-test-two", PARTNER_USER_ID),
    ],
)
def test_web_login_registers_new_device_and_bootstraps(
    client, database, username, password, user_id
):
    device_id = uuid4()
    auth = login(client, username, password, device_id, platform="web")

    assert auth["user_id"] == str(user_id)
    assert auth["device_id"] == str(device_id)
    with Session(database) as db:
        device = db.get(Device, device_id)
        assert device.platform == "web"
        assert device.user_id == user_id

    bootstrap_response = client.get(
        "/sync/bootstrap",
        headers={"Authorization": f"Bearer {auth['access_token']}"},
    )
    assert bootstrap_response.status_code == 200, bootstrap_response.text
    assert bootstrap_response.json()["tasks"] == []


def request(device_id, completed):
    record = _task_record(
        visibility="shared",
        workspace_id=DEFAULT_SHARED_WORKSPACE_ID,
        device_id=device_id,
        shared_completion_mode="both",
        completed_by_user_ids=completed,
    )
    return SyncPushRequest.model_validate(
        {
            "device_id": device_id,
            "changes": [
                {
                    "operation": "upsert",
                    "record": record,
                    "changed_task_fields": ["completed_by_user_ids", "is_completed"],
                }
            ],
        }
    )


def test_concurrent_writers_commit_in_cursor_order_and_bootstrap_is_consistent(
    database,
):
    ready = Event()
    commit_allowed = Event()
    first = Session(database, autoflush=False)

    @event.listens_for(first, "before_commit")
    def pause_before_outer_commit(db):
        if db.in_nested_transaction():
            return
        ready.set()
        assert commit_allowed.wait(10), "Timed out waiting for concurrency assertion"

    def write_first():
        try:
            return push_tasks(
                request(DEVICE_ID, [DEFAULT_CURRENT_USER_ID]),
                CurrentUser(DEFAULT_CURRENT_USER_ID, DEVICE_ID),
                first,
            )
        finally:
            first.close()

    def write_second():
        with Session(database, autoflush=False) as db:
            return push_tasks(
                request(OTHER_DEVICE_ID, [PARTNER_USER_ID]),
                CurrentUser(PARTNER_USER_ID, OTHER_DEVICE_ID),
                db,
            )

    def read_snapshot():
        with Session(database) as db:
            return bootstrap(CurrentUser(DEFAULT_CURRENT_USER_ID), db)

    with ThreadPoolExecutor(max_workers=3) as pool:
        writer_a = pool.submit(write_first)
        assert ready.wait(10)
        writer_b = pool.submit(write_second)
        reader = pool.submit(read_snapshot)
        try:
            deadline = time.monotonic() + 5
            blocked = 0
            while blocked < 2 and time.monotonic() < deadline:
                with database.connect() as conn:
                    blocked = conn.scalar(
                        text(
                            "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' "
                            "AND objid = 741802341 AND NOT granted"
                        )
                    )
                if blocked < 2:
                    time.sleep(0.01)
            assert blocked == 2, "Writer and bootstrap must wait for the first commit"
        finally:
            commit_allowed.set()
        assert writer_a.result(timeout=10).rejected == []
        assert writer_b.result(timeout=10).rejected == []
        snapshot = reader.result(timeout=10)

    # Each version emits one event per visible user; the snapshot may acquire the
    # lock before or after the second writer, but must describe exactly one state.
    task = snapshot.tasks[0]
    assert int(snapshot.cursor) == task.version * 2
    assert task.is_completed == (task.version == 2)
    with Session(database) as db:
        pulled = pull_tasks("0", CurrentUser(DEFAULT_CURRENT_USER_ID), db)
        assert [change.record.version for change in pulled.changes] == [1, 2]
        assert pulled.changes[-1].record.is_completed
        assert pulled.changes[-1].record.completed_at is not None


def test_permanent_deletion_cascades_and_rejects_offline_recreation(database):
    user = CurrentUser(DEFAULT_CURRENT_USER_ID, DEVICE_ID)
    with Session(database, autoflush=False) as db:
        push_tasks(request(DEVICE_ID, []), user, db)
        task = db.get(Task, TASK_ID)
        task.deleted_at = datetime.now(UTC) - timedelta(days=31)
        task.purge_after = datetime.now(UTC) - timedelta(days=1)
        db.commit()
        purge = request(DEVICE_ID, [])
        purge.changes[0].operation = SyncOperation.purge
        assert push_tasks(purge, user, db).rejected == []
        assert db.get(Task, TASK_ID) is None
        assert db.get(PurgedTask, TASK_ID) is not None
        result = push_tasks(request(DEVICE_ID, []), user, db)
        assert result.accepted == []
        assert result.purged_ids == [TASK_ID]
        assert db.get(Task, TASK_ID) is None


def test_http_auth_and_shared_task_subtask_round_trip(client, database):
    owner = login(client, "user1", "postgres-test-one", DEVICE_ID)
    partner = login(client, "user2", "postgres-test-two", OTHER_DEVICE_ID)
    owner_headers = {"Authorization": f"Bearer {owner['access_token']}"}
    partner_headers = {"Authorization": f"Bearer {partner['access_token']}"}
    record = _task_record(visibility="shared", workspace_id=DEFAULT_SHARED_WORKSPACE_ID)
    child = _subtask_record()
    child["created_at"] = "2026-01-02T03:04:05Z"
    child["position"] = 4
    record["subtasks"] = [child]
    pushed = client.post(
        "/sync/tasks",
        headers=owner_headers,
        json={
            "device_id": str(DEVICE_ID),
            "changes": [{"operation": "upsert", "record": record}],
        },
    )
    assert pushed.status_code == 200, pushed.text
    canonical = pushed.json()["accepted"][0]
    assert canonical["subtasks"][0]["position"] == 4
    assert canonical["subtasks"][0]["created_at"].startswith("2026-01-02T03:04:05")
    snapshot = client.get("/sync/bootstrap", headers=partner_headers)
    assert snapshot.status_code == 200
    assert [TaskRecord.model_validate(task) for task in snapshot.json()["tasks"]] == [
        TaskRecord.model_validate(canonical)
    ]
    pulled = client.get("/sync/tasks?cursor=0", headers=partner_headers)
    assert pulled.status_code == 200
    assert TaskRecord.model_validate(pulled.json()["changes"][0]["record"]) == (
        TaskRecord.model_validate(canonical)
    )
    refreshed = client.post(
        "/auth/refresh",
        json={"device_id": str(DEVICE_ID), "refresh_token": owner["refresh_token"]},
    )
    assert refreshed.status_code == 200
    with Session(database) as db:
        db.get(Device, DEVICE_ID).refresh_token_expires_at = datetime.now(UTC) - (
            timedelta(seconds=1)
        )
        db.commit()
    expired = client.post(
        "/auth/refresh",
        json={"device_id": str(DEVICE_ID), "refresh_token": owner["refresh_token"]},
    )
    assert expired.status_code == 401


def test_bad_child_identity_rejects_one_change_without_failing_batch(database):
    user = CurrentUser(DEFAULT_CURRENT_USER_ID, DEVICE_ID)
    first = request(DEVICE_ID, [])
    first.changes[0].record.subtasks = [SubtaskRecord.model_validate(_subtask_record())]
    with Session(database, autoflush=False) as db:
        assert push_tasks(first, user, db).rejected == []
        another = request(DEVICE_ID, [])
        another.changes[0].record.id = uuid4()
        stolen = db.get(Subtask, SUBTASK_ID)
        child = _subtask_record()
        child["task_id"] = str(another.changes[0].record.id)
        another.changes[0].record.subtasks = [SubtaskRecord.model_validate(child)]
        payload = another
        payload.changes.append(request(DEVICE_ID, [DEFAULT_CURRENT_USER_ID]).changes[0])
        result = push_tasks(payload, user, db)
        assert len(result.rejected) == 1
        assert len(result.accepted) == 1
        assert (
            db.get(Subtask, SUBTASK_ID).task_sync_id == stolen.task_sync_id == TASK_ID
        )
        assert db.get(Task, another.changes[0].record.id) is None


def test_pull_pages_advance_even_when_origin_device_filters_entire_page(database):
    record = request(DEVICE_ID, []).changes[0].record
    with Session(database) as db:
        db.add_all(
            [
                SyncEvent(
                    visible_user_id=DEFAULT_CURRENT_USER_ID,
                    entity_type="task",
                    entity_sync_id=TASK_ID,
                    operation=DbSyncOperation.upsert,
                    origin_device_id=DEVICE_ID if index < 500 else OTHER_DEVICE_ID,
                    payload=record.model_dump(mode="json"),
                    changed_task_fields=["title"],
                    changed_subtask_ids=[],
                )
                for index in range(501)
            ]
        )
        db.commit()
        user = CurrentUser(DEFAULT_CURRENT_USER_ID, DEVICE_ID)
        first = pull_tasks("0", user, db)
        assert first.changes == []
        assert first.has_more
        second = pull_tasks(first.cursor, user, db)
        assert len(second.changes) == 1
        assert not second.has_more
        assert int(second.cursor) > int(first.cursor)


def test_readiness_reports_missing_schema_while_liveness_stays_available(
    client, database
):
    assert client.get("/ready").status_code == 200
    with database.begin() as conn:
        conn.execute(
            text("ALTER TABLE purged_tasks RENAME TO unavailable_purged_tasks")
        )
    assert client.get("/ready").status_code == 503
    assert client.get("/health").status_code == 200
