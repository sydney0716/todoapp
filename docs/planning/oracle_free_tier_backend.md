# Oracle Free Tier Backend Direction

## Decision

Use an Oracle Free Tier server as the backend host for the two-user sync service.
This replaces the earlier open decision between Supabase and a custom backend.
The selected backend stack direction is a custom API plus Postgres on the
Oracle Free Tier server.

## Product Fit

The expected workload is small: two users, a few devices, low request volume,
and personal todo/habit data. That makes a simple single-server deployment more
appropriate than a larger managed architecture.

## Recommended Shape

- One small custom backend service exposing HTTPS APIs for auth, sync, export/import,
  and health checks.
- One server-side Postgres database for canonical synced data.
- Local-first Flutter clients continue to use SQLite and sync with the server.
- A reverse proxy terminates HTTPS and forwards requests to the app service.
- Automated database backups are required before production use.
- Logs and health checks should be simple but reliable enough to diagnose sync
  failures.

## Constraints

- Optimize for low maintenance and easy recovery.
- Avoid infrastructure that requires multiple always-on services unless there is
  a clear reason.
- Keep secrets out of the Flutter app and repository.
- Assume server capacity is limited; sync APIs should be efficient and
  idempotent.
- Plan for manual operational ownership: deploy, backup, restore, and update
  procedures must be documented.

## Open Technical Choices

- Backend language/framework.
- Postgres migration tool.
- Token/session mechanism for exactly two fixed accounts.
- Backup location and retention period.
- Reverse proxy and TLS certificate automation.
- Whether the server uses REST, RPC-style endpoints, or another API style.

## Approved Product Decisions

- Data model supports private items and shared items.
- There are two fixed human accounts:
  - User account: Android phone, iPad, Mac.
  - Partner account: iPhone, Mac.
- MVP conflict handling is local-first with `updated_at`/`version` metadata and
  last-write-wins.
- Trash is a first-class feature.
- Trash retention is user-selectable.
- Theme and time format stay per-device.

## Acceptance Criteria

- Android, iOS/iPadOS, and macOS clients can sync through the server.
- Offline client changes can be pushed safely after reconnect.
- Repeated sync requests do not create duplicate records.
- Backups can restore the service after server loss.
- Deployment and rollback steps are documented well enough for one maintainer.
