# Personal Todo sync backend

FastAPI and PostgreSQL provide authentication and task sync for two fixed accounts: `user1` and `user2`. Clients save tasks locally for offline use.

## API

| Endpoint | Purpose |
| --- | --- |
| `POST /auth/login` | Sign in and register a device session |
| `POST /auth/refresh` | Renew the session |
| `POST /auth/logout` | Revoke the device's refresh token |
| `POST /sync/tasks` | Apply changed task fields and subtasks; return server records |
| `GET /sync/tasks?cursor=...` | Pull changes since a cursor |
| `GET /sync/bootstrap` | Fetch visible tasks and a matching cursor |

Run **one API worker**. Login permits 10 attempts per IP and 20 per account per minute, including successful attempts. Excess requests return HTTP 429 with `Retry-After`; limits reset on restart.

- Both-person tasks update only the caller's completion flag. Conflicting edits to the same field follow server transaction order.
- Pulls contain up to 500 events. Follow the returned cursor while `has_more` is true, even when `changes` is empty.
- Purge requires owner permission and expired, acknowledged trash. Clients remove IDs returned in `purged_ids` to prevent deleted tasks from returning.
- There is no push delivery or event-history pruning. Monitor database growth; event history and purged IDs support old offline clients.

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

The migration command applies pending SQL transactionally and records it in `schema_migrations`. Keep `AUTO_MIGRATE=false` and apply migrations explicitly before production restarts.

## Checks

```bash
python -m pytest
python -m ruff check app tests
```

Default tests use fakes. For database integration tests, use a disposable PostgreSQL database; tests create and drop temporary schemas:

```bash
TODOAPP_TEST_DATABASE_URL=postgresql+psycopg://user:password@localhost:5432/personaltodo_test python -m pytest
```

See [the deployment guide](deploy/README_ORACLE_VM.md) for hosting, upgrades, health checks, and backups.
