# Approved MVP Sync Protocol

This document freezes the first sync MVP decisions for the Flutter todo/habit
app. The goal is to prevent the app, server, and UI work from diverging.

## Approved Decisions

- Data model supports private items and shared items.
- Auth uses two fixed human accounts.
- Each account can use multiple devices.
- User devices: Android phone, iPad, Mac.
- Partner devices: iPhone, Mac.
- Backend runs on Oracle Free Tier.
- Backend stack direction is custom API plus Postgres.
- MVP sync is local-first.
- MVP conflict policy is last-write-wins using `updated_at` and `version`.
- Delete moves items to a visible Trashcan.
- Trash retention is user-selectable.
- Theme and time format stay per-device.

## Data Ownership

Each task or habit belongs to one visibility scope:

- `private`: visible only to the owner account.
- `shared`: visible to both fixed accounts.

Required ownership fields:

- `owner_user_id`
- `visibility`: `private` or `shared`
- `workspace_id` for shared data
- `created_by_user_id`
- `updated_by_user_id`

Display settings do not sync for MVP:

- Theme
- Time format
- Completed-item visibility
- Layout or platform preferences

## Local-First Save Rules

- User actions write to local SQLite first.
- UI updates immediately after the local save.
- Changed records are marked pending sync.
- App remains usable offline.
- Sync retries automatically when network is available.

Required sync fields:

- `sync_id`
- `created_at`
- `updated_at`
- `version`
- `deleted_at`
- `sync_status`
- `last_synced_at`
- `device_id`

## Sync Timing

Sync should run:

- On app launch.
- On app resume.
- After create/update/delete when online.
- Periodically while the app is open.
- When the user taps manual Sync now.
- After reconnecting from offline state.

## Conflict Policy

MVP uses last-write-wins.

- Compare `updated_at` and/or `version`.
- Newer server-accepted change wins.
- Subtasks and habit completions should sync as separate records where possible.
- If one device edits an item that another device moved to Trash, Trash wins unless the item is restored.
- Full manual conflict merge is not required for MVP.

## Trashcan / Delete Protocol

- Delete moves item to Trashcan.
- Trash items remain recoverable until permanent deletion.
- Retention period is user-selectable.
- Trashcan must be visible in the app.
- Restore clears `deleted_at` and syncs as an update.
- Habit completions and subtasks remain linked while the parent item is in Trash.
- Permanent deletion removes the parent and dependent records.
- Permanent deletion occurs only after:
  - retention period expires, and
  - delete tombstone has synced successfully.

Recommended initial retention options:

- 7 days
- 30 days
- 90 days
- Never automatically delete

## Backend Server Direction

Use a small custom API service plus Postgres on Oracle Free Tier.

Core backend responsibilities:

- Fixed-account login and token/session management.
- Per-device refresh/session tracking.
- Private item isolation.
- Shared item access for both fixed accounts.
- Idempotent sync writes.
- Incremental pull by cursor.
- Trashcan, restore, and permanent delete enforcement.
- Backups and restore documentation before production use.

Tasks-first MVP endpoints:

- `POST /auth/login`
- `POST /auth/refresh`
- `POST /auth/logout`
- `GET /sync/bootstrap`
- `GET /sync/tasks?cursor=...`
- `POST /sync/tasks`
- `GET /trash`
- `POST /tasks/:id/restore`
- `DELETE /tasks/:id/permanent`
- `PUT /settings/trash-retention`
- `GET /health`

Core Postgres tables for the tasks-first MVP:

- `users`
- `devices`
- `tasks`
- `subtasks`
- `sync_cursors` or `sync_events`
- `trash_retention_settings`

Habits and habit completions should follow after task sync is working end to
end.

## Backend App Direction

Keep existing integer local IDs for legacy Room compatibility, then add sync
identity and metadata.

Common local fields for synced tables:

- `sync_id TEXT NOT NULL UNIQUE`
- `owner_user_id TEXT NOT NULL`
- `visibility TEXT NOT NULL`
- `workspace_id TEXT NULL`
- `updated_at INTEGER NOT NULL`
- `version INTEGER NOT NULL DEFAULT 1`
- `sync_status TEXT NOT NULL DEFAULT 'pending'`
- `deleted_at INTEGER NULL`
- `purge_after INTEGER NULL`
- `last_synced_at INTEGER NULL`

Add a local `sync_queue` table:

- `id`
- `entity_type`
- `entity_sync_id`
- `operation`: `upsert`, `delete`, `purge`
- `payload_json`
- `attempt_count`
- `last_error`
- `created_at`
- `next_attempt_at`

Queue behavior:

- Every local write updates the entity and appends a queue item in one SQLite transaction.
- Sync pushes pending queue items, then pulls server changes.
- Server response updates `version`, `updated_at`, `sync_status`, and clears successful queue items.
- Failed sync preserves queue state for retry.

Migration behavior:

- Existing local-only rows are backfilled with generated `sync_id`.
- Existing rows default to `visibility = private`.
- Existing rows become `sync_status = pending` so they upload once after login.
- Starter content must not duplicate migrated data.

## Frontend Direction

Visibility UI:

- Show Private with a one-person indicator.
- Show Shared with a two-person indicator.
- Editors need a Private / Shared segmented control.
- Detail screens should show last edited by and sync metadata.

Sync UI:

- Top-level status: Synced, Syncing, Offline, Sync failed, Local changes pending.
- Tapping status opens sync details: last sync time, pending count, current device, retry action.
- Per-item pending/conflict indicators should stay subtle.

Trashcan UI:

- Add Trashcan as a visible navigation destination.
- Show deleted date and auto-delete date.
- Provide Restore and Delete permanently actions.
- Main-list delete should say Moved to Trashcan with Undo.

Platform navigation:

- Android phone / iPhone: single-column layout with contextual FAB.
- iPad: NavigationRail with list/detail.
- Mac: persistent sidebar with list/detail/editor and keyboard shortcuts.

## Acceptance Scenarios

### A1. Private Task Syncs Only To Owner

1. User creates a private task on Android.
2. User opens iPad or Mac.
3. Task appears after sync.
4. Partner opens iPhone or Mac.
5. Task does not appear.

Pass: private task is visible only on user's devices.

### A2. Shared Task Syncs To Both Users

1. User creates a shared task on Android.
2. Partner opens iPhone.
3. Shared task appears after sync.
4. Partner edits the title.
5. User sees edited title after sync.

Pass: shared item is visible and editable by both users.

### A3. Offline Create Then Sync

1. User goes offline on Android.
2. User creates a shared task.
3. Task appears locally with pending sync state.
4. User reconnects.
5. Partner sees the task after sync.

Pass: offline-created item syncs without duplicate records.

### A4. Last-Write-Wins Conflict

1. User and partner both edit the same shared task on separate devices.
2. Both devices sync.
3. The newer accepted update wins.
4. All devices converge to the same title/content.

Pass: no duplicate task is created; all devices show the same final value.

### A5. Trash Wins Over Edit

1. User moves a shared task to Trashcan.
2. Partner edits the same task before receiving the trash update.
3. Both devices sync.
4. Task remains in Trashcan.

Pass: Trash state wins over stale edit.

### A6. Restore From Trashcan

1. User moves a task to Trashcan.
2. Partner sees it in Trashcan after sync.
3. Partner restores it.
4. Both users see it active again after sync.

Pass: restore clears Trash state across devices.

### A7. Retention-Based Permanent Delete

1. User moves a task to Trashcan.
2. Tombstone syncs successfully.
3. Retention period expires.
4. Permanent delete job runs.
5. Task no longer appears on any device, including Trashcan.

Pass: item is permanently removed only after synced tombstone and retention expiry.

### A8. Per-Device Settings Do Not Sync

1. User sets dark theme on Android.
2. User opens iPad.
3. iPad keeps its own theme setting.
4. User changes time format on Mac.
5. Android setting does not change.

Pass: display preferences remain device-local.

### A9. Multi-Device Same User

1. User creates a task on Android.
2. User edits it on Mac.
3. User completes it on iPad.
4. Android receives final completed state after sync.

Pass: same user can operate across multiple devices consistently.

### A10. Sync Failure Recovery

1. Server is unavailable.
2. User edits several items.
3. App keeps local changes pending.
4. Server returns.
5. App retries sync.
6. All devices converge.

Pass: no local data is lost during server outage.

## Immediate Implementation Order

1. Build tasks-first backend skeleton and schema.
2. Add local sync metadata and migration path.
3. Add local sync queue.
4. Implement task/subtask sync bootstrap, push, and pull.
5. Add basic account, sync status, Private/Shared, and Trashcan UI.
6. Validate tasks sync end-to-end across two accounts and multiple devices.
7. Add habits and habit completions after task sync is stable.
