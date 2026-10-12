#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL is required}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/personal_todo_backups}"
source "$(dirname "$0")/backup_common.sh"
# Convert SQLAlchemy URLs without exposing credentials in command-line arguments.
python3 "$(dirname "$0")/dump_postgres.py" "$backup_temp"
pg_restore --list "$backup_temp" > /dev/null
finish_backup
