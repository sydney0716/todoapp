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
- Confirmed remaining risk: Android widget mutations still need a sync-queue
  path, top-level sync status UI is still missing, and a real Postgres
  migration smoke test has not been run.
