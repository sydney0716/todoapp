CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'visibility') THEN
    CREATE TYPE visibility AS ENUM ('private', 'shared');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sync_operation') THEN
    CREATE TYPE sync_operation AS ENUM ('upsert', 'delete', 'restore', 'purge');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  display_name TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS workspaces (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS workspace_members (
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY (workspace_id, user_id)
);

CREATE TABLE IF NOT EXISTS devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_name TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'ipados', 'macos')),
  refresh_token_hash TEXT NOT NULL,
  refresh_token_expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '60 days'),
  last_seen_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tasks (
  sync_id UUID PRIMARY KEY,
  owner_user_id UUID NOT NULL REFERENCES users(id),
  visibility visibility NOT NULL,
  workspace_id UUID REFERENCES workspaces(id),
  created_by_user_id UUID NOT NULL REFERENCES users(id),
  updated_by_user_id UUID NOT NULL REFERENCES users(id),
  title TEXT NOT NULL CHECK (length(trim(title)) > 0),
  note TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT '',
  is_completed BOOLEAN NOT NULL DEFAULT FALSE,
  shared_completion_mode TEXT NOT NULL DEFAULT 'single',
  completed_by_user_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
  due_at TIMESTAMPTZ,
  reminder_option TEXT NOT NULL DEFAULT 'none',
  reminder_value INTEGER,
  completed_at TIMESTAMPTZ,
  device_id UUID REFERENCES devices(id),
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0),
  deleted_at TIMESTAMPTZ,
  purge_after TIMESTAMPTZ,
  server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ck_tasks_visibility_workspace CHECK (
    (visibility = 'private' AND workspace_id IS NULL)
    OR (visibility = 'shared' AND workspace_id IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS ix_tasks_owner_visibility
  ON tasks(owner_user_id, visibility);
CREATE INDEX IF NOT EXISTS ix_tasks_workspace
  ON tasks(workspace_id);
CREATE INDEX IF NOT EXISTS ix_tasks_updated
  ON tasks(updated_at);
CREATE INDEX IF NOT EXISTS ix_tasks_deleted
  ON tasks(deleted_at);

CREATE TABLE IF NOT EXISTS subtasks (
  sync_id UUID PRIMARY KEY,
  task_sync_id UUID NOT NULL REFERENCES tasks(sync_id) ON DELETE CASCADE,
  title TEXT NOT NULL CHECK (length(trim(title)) > 0),
  is_completed BOOLEAN NOT NULL DEFAULT FALSE,
  due_at TIMESTAMPTZ,
  position INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0),
  deleted_at TIMESTAMPTZ,
  server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_subtasks_task
  ON subtasks(task_sync_id);
CREATE INDEX IF NOT EXISTS ix_subtasks_updated
  ON subtasks(updated_at);

CREATE TABLE IF NOT EXISTS sync_events (
  id BIGSERIAL PRIMARY KEY,
  visible_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('task', 'subtask')),
  entity_sync_id UUID NOT NULL,
  operation sync_operation NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  server_created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_sync_events_visible_user_cursor
  ON sync_events(visible_user_id, id);
CREATE INDEX IF NOT EXISTS ix_sync_events_entity
  ON sync_events(entity_type, entity_sync_id);

CREATE TABLE IF NOT EXISTS trash_retention_settings (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  retention_days INTEGER CHECK (retention_days IN (7, 30, 90) OR retention_days IS NULL),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
