ALTER TABLE devices
  ADD COLUMN IF NOT EXISTS refresh_token_expires_at TIMESTAMPTZ;

UPDATE devices
SET refresh_token_expires_at = now() + interval '60 days'
WHERE refresh_token_expires_at IS NULL;

ALTER TABLE devices
  ALTER COLUMN refresh_token_expires_at SET NOT NULL;
