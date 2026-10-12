#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-server/deploy/docker-compose.oracle.yml}"
ENV_FILE="${ENV_FILE:-server/.env}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/personal_todo_backups}"
source "$(dirname "$0")/../scripts/backup_common.sh"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres sh -lc 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' > "$backup_temp"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres pg_restore --list < "$backup_temp" > /dev/null
finish_backup
