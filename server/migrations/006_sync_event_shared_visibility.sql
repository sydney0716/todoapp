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
