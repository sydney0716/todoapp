# Shared by the host and Docker backup entrypoints.
if [[ -n "${BACKUP_RETENTION_DAYS:-}" ]]; then
  [[ "$BACKUP_RETENTION_DAYS" =~ ^[1-9][0-9]*$ ]] || { echo "BACKUP_RETENTION_DAYS must be a positive integer" >&2; exit 1; }
fi
mkdir -p "$BACKUP_DIR"
backup_timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_temp="$(mktemp "$BACKUP_DIR/.personal_todo_${backup_timestamp}.XXXXXX")"
backup_file="$BACKUP_DIR/personal_todo_${backup_timestamp}_${backup_temp##*.}.dump"
trap 'rm -f "$backup_temp"' EXIT

finish_backup() {
  test -s "$backup_temp"
  mv "$backup_temp" "$backup_file"
  if [[ -n "${BACKUP_RETENTION_DAYS:-}" ]]; then
    find "$BACKUP_DIR" -type f -name 'personal_todo_*.dump' -mtime "+$BACKUP_RETENTION_DAYS" -delete
  fi
  printf '%s\n' "$backup_file"
}
