# Project

Updated: 2026-08-13

## Goal

Personal Todo is a Flutter-first personal task app for two users across Android,
iOS/iPadOS, and macOS, backed by a small FastAPI/Postgres sync service.

## Users

- Primary user and partner using a fixed two-account model.
- Target devices: Android phone, iPad, iPhone, and Mac.

## Scope

- In: Flutter client, local SQLite persistence, native Android/macOS widgets,
  FastAPI sync backend, Postgres schema/migrations, deployment docs, tests, and
  project planning docs.
- Out: broad public signup, real-time websocket collaboration, app-store release
  operations, and large product redesigns unless separately approved.

## Success

- Existing local data remains safe while the app moves toward two-user sync.
- App and server contracts support private/shared tasks, offline-first updates,
  trash/restore, and predictable conflict behavior.
- Repo review identifies likely errors, stale or over-engineered code, and
  validation gaps with file-level evidence.

## Constraints

- Confirmed: MVP sync uses two fixed human accounts, local-first behavior,
  last-write-wins via `updated_at`/`version`, and Oracle Free Tier hosting.
- Confirmed: theme, time format, completed-item visibility, layout, and platform
  preferences remain per-device for MVP.
- Confirmed 2026-08-13 remediation: task sync now preserves client
  `updated_at`/`version` LWW semantics, sends changed subtask IDs, gates purge
  by retention, keeps logout from deleting referenced device rows, filters
  local private tasks by active user, and preserves queued local changes during
  bootstrap reconciliation.
- Confirmed 2026-08-13 native remediation: Android widget task/subtask
  completion now enters Flutter repository actions instead of writing SQLite
  directly, and widget task reads filter active-user private items.
- Confirmed 2026-08-13 P1/P2 remediation: Home now exposes sync status/details
  for pending, failed, offline, retry, in-flight, and last-sync states; app and
  server sync field metadata are covered by contract tests.
- Confirmed 2026-08-13 P3 cleanup: public/server/deploy docs now match the
  implemented sync surface, default server tests are documented as fake-backed,
  and the `psycopg` requirements bound matches `pyproject.toml`.
- Confirmed remaining risk: a real Postgres migration smoke test has not been
  run locally; an opt-in `TODOAPP_TEST_DATABASE_URL` smoke test now exists.
