from sqlalchemy import text

from .config import get_settings
from .database import get_sessionmaker


def apply_runtime_migrations() -> None:
    if not get_settings().auto_migrate:
        return

    sessionmaker = get_sessionmaker()
    with sessionmaker() as db:
        db.execute(
            text(
                """
                ALTER TABLE sync_events
                  ADD COLUMN IF NOT EXISTS origin_device_id UUID REFERENCES devices(id),
                  ADD COLUMN IF NOT EXISTS changed_task_fields JSONB
                    NOT NULL DEFAULT '[]'::jsonb,
                  ADD COLUMN IF NOT EXISTS changed_subtask_ids JSONB
                    NOT NULL DEFAULT '[]'::jsonb
                """
            )
        )
        db.execute(
            text(
                """
                ALTER TABLE tasks
                  ADD COLUMN IF NOT EXISTS shared_completion_mode TEXT
                    NOT NULL DEFAULT 'single',
                  ADD COLUMN IF NOT EXISTS completed_by_user_ids JSONB
                    NOT NULL DEFAULT '[]'::jsonb
                """
            )
        )
        db.execute(
            text(
                """
                ALTER TABLE subtasks
                  ADD COLUMN IF NOT EXISTS due_at TIMESTAMPTZ
                """
            )
        )
        db.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS ix_sync_events_origin_device
                  ON sync_events(origin_device_id)
                """
            )
        )
        db.execute(
            text(
                """
                DELETE FROM workspace_members AS member
                WHERE NOT EXISTS (
                  SELECT 1 FROM users AS app_user
                  WHERE app_user.id = member.user_id
                )
                OR NOT EXISTS (
                  SELECT 1 FROM workspaces AS workspace
                  WHERE workspace.id = member.workspace_id
                )
                """
            )
        )
        db.execute(
            text(
                """
                DO $$
                DECLARE
                  constraint_record record;
                  index_record record;
                BEGIN
                  FOR constraint_record IN
                    SELECT constraint_info.conname
                    FROM pg_constraint AS constraint_info
                    WHERE constraint_info.conrelid = 'sync_events'::regclass
                      AND constraint_info.contype = 'u'
                      AND EXISTS (
                        SELECT 1
                        FROM unnest(constraint_info.conkey)
                          AS constrained_column(attnum)
                        JOIN pg_attribute AS attribute_info
                          ON attribute_info.attrelid = constraint_info.conrelid
                         AND attribute_info.attnum = constrained_column.attnum
                        WHERE attribute_info.attname = 'entity_sync_id'
                      )
                      AND NOT EXISTS (
                        SELECT 1
                        FROM unnest(constraint_info.conkey)
                          AS constrained_column(attnum)
                        JOIN pg_attribute AS attribute_info
                          ON attribute_info.attrelid = constraint_info.conrelid
                         AND attribute_info.attnum = constrained_column.attnum
                        WHERE attribute_info.attname = 'visible_user_id'
                      )
                  LOOP
                    EXECUTE format(
                      'ALTER TABLE sync_events DROP CONSTRAINT IF EXISTS %I',
                      constraint_record.conname
                    );
                  END LOOP;

                  FOR index_record IN
                    SELECT indexname
                    FROM pg_indexes
                    WHERE schemaname = current_schema()
                      AND tablename = 'sync_events'
                      AND indexdef ILIKE 'CREATE UNIQUE INDEX%'
                      AND indexdef ILIKE '%entity_sync_id%'
                      AND indexdef NOT ILIKE '%visible_user_id%'
                  LOOP
                    EXECUTE format('DROP INDEX IF EXISTS %I', index_record.indexname);
                  END LOOP;
                END $$;
                """
            )
        )
        db.commit()
