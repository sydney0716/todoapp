from __future__ import annotations

import os
from pathlib import Path
from uuid import uuid4

import pytest
from sqlalchemy import create_engine, text

DATABASE_URL = os.getenv("TODOAPP_TEST_DATABASE_URL")

if not DATABASE_URL:
    pytest.skip(
        "Set TODOAPP_TEST_DATABASE_URL to run Postgres migration smoke tests.",
        allow_module_level=True,
    )


def test_postgres_migrations_support_auth_task_sync_smoke():
    engine = create_engine(DATABASE_URL, pool_pre_ping=True)
    schema_name = f"todoapp_smoke_{uuid4().hex}"
    quoted_schema = f'"{schema_name}"'

    with engine.connect().execution_options(isolation_level="AUTOCOMMIT") as conn:
        conn.exec_driver_sql(f"CREATE SCHEMA {quoted_schema}")
        try:
            conn.exec_driver_sql(f"SET search_path TO {quoted_schema}, public")
            for migration in sorted(_migration_dir().glob("*.sql")):
                conn.exec_driver_sql(migration.read_text())

            conn.execute(
                text(
                    """
                    INSERT INTO users (
                      id, username, password_hash, display_name
                    )
                    VALUES (
                      '00000000-0000-4000-8000-000000000001',
                      'user1',
                      'hash',
                      'User 1'
                    )
                    """
                )
            )
            conn.execute(
                text(
                    """
                    INSERT INTO devices (
                      id,
                      user_id,
                      device_name,
                      platform,
                      refresh_token_hash
                    )
                    VALUES (
                      '11111111-1111-4111-8111-111111111111',
                      '00000000-0000-4000-8000-000000000001',
                      'Android',
                      'android',
                      'refresh-hash'
                    )
                    """
                )
            )
            conn.execute(
                text(
                    """
                    INSERT INTO tasks (
                      sync_id,
                      owner_user_id,
                      visibility,
                      created_by_user_id,
                      updated_by_user_id,
                      title,
                      created_at,
                      updated_at,
                      version,
                      device_id
                    )
                    VALUES (
                      '22222222-2222-4222-8222-222222222222',
                      '00000000-0000-4000-8000-000000000001',
                      'private',
                      '00000000-0000-4000-8000-000000000001',
                      '00000000-0000-4000-8000-000000000001',
                      'Smoke task',
                      now(),
                      now(),
                      1,
                      '11111111-1111-4111-8111-111111111111'
                    )
                    """
                )
            )
            conn.execute(
                text(
                    """
                    INSERT INTO sync_events (
                      visible_user_id,
                      entity_type,
                      entity_sync_id,
                      operation,
                      payload,
                      origin_device_id,
                      changed_task_fields,
                      changed_subtask_ids
                    )
                    VALUES (
                      '00000000-0000-4000-8000-000000000001',
                      'task',
                      '22222222-2222-4222-8222-222222222222',
                      'upsert',
                      '{}'::jsonb,
                      '11111111-1111-4111-8111-111111111111',
                      '["title"]'::jsonb,
                      '[]'::jsonb
                    )
                    """
                )
            )

            assert (
                conn.scalar(
                    text(
                        """
                        SELECT changed_task_fields ->> 0
                        FROM sync_events
                        WHERE entity_sync_id =
                          '22222222-2222-4222-8222-222222222222'
                        """
                    )
                )
                == "title"
            )
        finally:
            conn.exec_driver_sql(
                f"DROP SCHEMA IF EXISTS {quoted_schema} CASCADE"
            )


def _migration_dir() -> Path:
    return Path(__file__).resolve().parents[1] / "migrations"
