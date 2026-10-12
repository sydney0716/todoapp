-- Permanent IDs prevent offline devices from recreating deleted tasks.
CREATE TABLE IF NOT EXISTS purged_tasks (
  sync_id UUID PRIMARY KEY,
  owner_user_id UUID NOT NULL,
  workspace_id UUID,
  purged_at TIMESTAMPTZ NOT NULL
);
-- A visibility-loss event also uses purge, but its payload is not in trash.
INSERT INTO purged_tasks (sync_id, owner_user_id, workspace_id, purged_at)
SELECT DISTINCT ON (entity_sync_id)
  entity_sync_id, (payload->>'owner_user_id')::uuid,
  (payload->>'workspace_id')::uuid, server_created_at
FROM sync_events
WHERE operation = 'purge' AND payload->>'deleted_at' IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM tasks WHERE tasks.sync_id = entity_sync_id)
ORDER BY entity_sync_id, id DESC
ON CONFLICT DO NOTHING;
