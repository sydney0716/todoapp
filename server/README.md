# Personal Todo sync backend

FastAPI and PostgreSQL provide authentication and canonical task state for two fixed accounts. SQLite on each device keeps tasks available offline and queues local changes.

## Sync behavior

- `POST /auth/login`, `POST /auth/refresh`, and `POST /auth/logout` manage device-bound sessions. Login initializes the configured `user1` and `user2` accounts; ordinary sync does not rehash their passwords.
- Login allows 10 attempts per IP and 20 per account in a one-minute window, including successful attempts. Excess requests return HTTP 429 with `Retry-After` before password hashing. Blocked requests do not extend the window; refresh and sync are unaffected. Counters are bounded, held in memory, and reset on process restart. Run one API worker; multiple workers would need a shared limiter.
- `POST /sync/tasks` accepts changed task fields and child IDs and returns canonical records. Only the caller's completion flag changes for Both-person tasks. Conflicting edits to the same field follow server transaction order, rather than device timestamps. Legacy payloads without changed-field metadata retain version-based compatibility.
- `GET /sync/tasks?cursor=...` returns up to 500 events plus `has_more`. The cursor advances through own-device events even when those events are filtered from `changes`; clients must follow `has_more` even for empty pages.
- `GET /sync/bootstrap` returns visible tasks and a matching cursor. PostgreSQL transaction advisory locks serialize writers and bootstrap reads to prevent skipping uncommitted earlier events. This is intentionally simple for two users.
- Purge requires owner permission and expired acknowledged trash. Durable `purged_tasks` rows prevent stale offline clients from recreating a deleted ID. Push returns `purged_ids` so those clients remove the stale data.
- Task versions advance for child-only changes. Child order, creation time, and completion time survive sync. Child IDs cannot be reassigned to another parent.

`/health` checks process liveness. `/ready` checks database access and required tables, returning HTTP 503 if unavailable or uninitialized. The Docker health check uses `/ready`.

There is no background push delivery or sync-event pruning. Event history and purge tombstones are retained so old offline clients can reconnect safely. Monitor database size before introducing a pruning protocol. Completed-task retention preferences remain device-local; habits and server retention-setting APIs remain deferred.

## Local development

From `server/`:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -e '.[dev]'
cp .env.example .env
```

Set `DATABASE_URL` to your local PostgreSQL instance, set `JWT_SECRET`, `USER1_PASSWORD`, and `USER2_PASSWORD`, then run:

```bash
python -m app.runtime_schema
uvicorn app.main:app --reload
```

The migration command runs versioned SQL transactionally and records applied filenames in `schema_migrations`. It supports fresh databases and existing databases where the old SQL was applied manually. `AUTO_MIGRATE=false` is the default; optionally enable it for development startup. Apply new migrations explicitly before restarting production.

Runtime and development dependencies are declared once in `pyproject.toml`; `requirements.txt` installs that package. The Docker image installs runtime dependencies only and includes migrations.

## Checks

```bash
python -m pytest
python -m ruff check app tests
```

The default tests use fakes. To exercise migrations, constraints, actual HTTP auth/sync, purge protection, bounded pulls, and concurrent writer/bootstrap ordering, use an isolated PostgreSQL database:

```bash
TODOAPP_TEST_DATABASE_URL=postgresql+psycopg://user:password@localhost:5432/personaltodo_test python -m pytest
```

PostgreSQL tests create temporary schemas and drop them afterward. Use a disposable test database, not production. See the root [verification summary](../README.md#review-and-verification) for the last verified counts and native-build limits.

## Deployment and backups

Follow [the Oracle VM guide](deploy/README_ORACLE_VM.md) for first setup, upgrades, backup scheduling, and a restore check. Both backup entrypoints validate the dump before moving a temporary file into its final name. Set `BACKUP_RETENTION_DAYS` to enable rotation; the default retains all dumps.

The host script accepts the application's `postgresql+psycopg://` URL and passes credentials to `pg_dump` through its environment. Host tools require `pg_dump` and `pg_restore` compatible with the database version. Keep a verified backup off the VM; a local backup shares the VM's failure risk.
