-- Retain the legacy membership repair previously performed at every startup.
DELETE FROM workspace_members AS member
WHERE NOT EXISTS (SELECT 1 FROM users WHERE users.id = member.user_id)
   OR NOT EXISTS (SELECT 1 FROM workspaces WHERE workspaces.id = member.workspace_id);

UPDATE tasks SET completed_at = updated_at WHERE is_completed AND completed_at IS NULL;
