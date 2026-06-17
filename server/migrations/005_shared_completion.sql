ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS shared_completion_mode TEXT NOT NULL DEFAULT 'single',
  ADD COLUMN IF NOT EXISTS completed_by_user_ids JSONB NOT NULL DEFAULT '[]'::jsonb;
