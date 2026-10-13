ALTER TABLE devices
  DROP CONSTRAINT IF EXISTS devices_platform_check,
  ADD CONSTRAINT devices_platform_check
    CHECK (platform IN ('android', 'ios', 'ipados', 'macos', 'web'));
