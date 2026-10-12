ALTER TABLE sync_events
  ADD COLUMN IF NOT EXISTS origin_device_id UUID REFERENCES devices(id),
  ADD COLUMN IF NOT EXISTS changed_task_fields JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS changed_subtask_ids JSONB NOT NULL DEFAULT '[]'::jsonb;

CREATE INDEX IF NOT EXISTS ix_sync_events_origin_device
  ON sync_events(origin_device_id);
