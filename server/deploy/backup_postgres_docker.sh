#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-server/deploy/docker-compose.oracle.yml}"
ENV_FILE="${ENV_FILE:-server/.env}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/personal_todo_backups}"

mkdir -p "$BACKUP_DIR"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_file="$BACKUP_DIR/personal_todo_$timestamp.dump"

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres sh -lc 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' > "$backup_file"

echo "$backup_file"
