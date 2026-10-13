# Oracle VM deployment

Docker Compose runs the API, PostgreSQL, and Caddy for HTTPS. Build Flutter clients on your development machine.

## Setup

Point your domain at the VM. Allow TCP 80 and 443 through Oracle's security rules and the VM firewall; restrict SSH to your own IP. Keep API and PostgreSQL ports unpublished: the API trusts Caddy's forwarded client addresses for login limits. Configure explicit trusted proxies if you add another proxy.

Install [Docker Engine and the Compose plugin](https://docs.docker.com/engine/install/), then:

```bash
git clone https://github.com/sydney0716/todoapp.git personal_todo
cd personal_todo
cp server/.env.example server/.env
dc() { docker compose --env-file server/.env -f server/deploy/docker-compose.oracle.yml "$@"; }
```

Set the database credentials, `JWT_SECRET`, `USER1_PASSWORD`, `USER2_PASSWORD`, and `PERSONAL_TODO_DOMAIN` in `server/.env`. Use distinct account passwords, a long random JWT secret, and a URL-safe database password (for example, `openssl rand -hex 32`). Never commit this file.

Run commands from the repository root and define `dc` again in each new terminal. Replace `<your-domain>` in the examples.

## First deployment

```bash
dc up -d postgres
dc build api
dc run --rm api python -m app.runtime_schema
dc up -d
curl --fail 'https://<your-domain>/ready'
```

`/ready` checks the database and required tables; expect `{"status":"ok"}`. `/health` checks process liveness. Compose uses readiness checks to order startup. See [migration behavior](../README.md#local-development). Keep the `personaltodo_pgdata` volume when upgrading.

## Upgrades

Back up first and retain the previous code revision. Stop if a backup or migration fails.

```bash
bash server/deploy/backup_postgres_docker.sh
git pull
dc stop api
dc build api
dc run --rm api python -m app.runtime_schema
dc up -d
curl --fail 'https://<your-domain>/ready'
```

Check `dc logs --tail=100 api` and `dc ps` if needed. Update the server before clients. Install over existing apps with the same application IDs, signing identities, and app-group settings to preserve local data.

## Web hosting

On your development machine:

```bash
bash scripts/build_web.sh
```

After updating the API and applying migrations, upload all of `build/web/` to `server/deploy/web/releases/BUILD_ID/` on the VM. Activate it there:

```bash
ln -sfn releases/BUILD_ID server/deploy/web/current
dc up -d --no-deps caddy
curl --fail 'https://<your-domain>/app/manifest.json'
```

Caddy serves the web app at `/app/` and the API on the same origin. For later static-only updates, switch the symlink after uploading; Caddy needs no restart. Keep the previous release for rollback. Close all tabs and reopen the Home Screen app to activate an available update.

## Changing the domain

- Point the new domain at the VM. Set `PERSONAL_TODO_DOMAIN` to it and `PERSONAL_TODO_PREVIOUS_DOMAIN` to the old domain in `server/.env`. Run `dc up -d --no-deps caddy` and verify HTTPS.
- Build native updates with `TODO_API_BASE_URL` and `TODO_PREVIOUS_API_BASE_URL` in a gitignored build configuration. This migrates the saved old URL while preserving sessions and cursors.
- Web users should sync pending edits at the old address before signing in and adding the new address to the Home Screen. Remove `PERSONAL_TODO_PREVIOUS_DOMAIN` and recreate Caddy once all devices have moved.

## Backups

```bash
BACKUP_DIR="$HOME/personal_todo_backups" BACKUP_RETENTION_DAYS=30 bash server/deploy/backup_postgres_docker.sh
```

The script validates the dump before finalizing it and rotates files only after success. Omit `BACKUP_RETENTION_DAYS` to retain all dumps. Validation does not replace a restore check; keep copies off the VM. The repository does not schedule backups or off-VM copying.

After running a first backup, add a daily entry with `crontab -e`, replacing `VM_USER` and the clone path:

```cron
15 3 * * * cd /home/VM_USER/personal_todo && BACKUP_DIR=/home/VM_USER/personal_todo_backups BACKUP_RETENTION_DAYS=30 /usr/bin/bash server/deploy/backup_postgres_docker.sh >> /home/VM_USER/personal_todo_backups/backup.log 2>&1
```

Copy backups to another machine:

```bash
mkdir -p "$HOME/personal_todo_backups"
rsync -av VM_USER@VM_PUBLIC_IP:~/personal_todo_backups/ "$HOME/personal_todo_backups/"
```

For host-installed PostgreSQL, export `DATABASE_URL` and use `server/scripts/backup_postgres.sh` with compatible `pg_dump` and `pg_restore` tools.

## Restore check

Use a disposable database and replace the dump path:

```bash
dc exec -T postgres sh -lc 'createdb -U "$POSTGRES_USER" personaltodo_restore_check'
dc exec -T postgres sh -lc 'pg_restore --exit-on-error --no-owner --no-privileges -U "$POSTGRES_USER" -d personaltodo_restore_check' < /path/to/personal_todo_backup.dump
dc exec -T postgres sh -lc 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d personaltodo_restore_check -c "SELECT count(*) FROM tasks; SELECT count(*) FROM subtasks; SELECT count(*) FROM purged_tasks;"'
```

Inspect representative tasks and subtasks, then remove the test database:

```bash
dc exec -T postgres sh -lc 'dropdb -U "$POSTGRES_USER" personaltodo_restore_check'
```

A production restore requires stopping app writes and confirming the target database separately.

## Release checks

- Verify offline edits, Both-person completion, and partner changes across devices.
- Check widgets, reminders, and re-login after session expiry; cached tasks and pending changes should remain.
- Confirm readiness and restore a recent backup into a separate database.

## References

- [Oracle Compute and SSH](https://docs.oracle.com/iaas/Content/Compute/Tasks/instances.htm)
- [Oracle network security rules](https://docs.oracle.com/iaas/Content/Network/Concepts/securityrules.htm)
