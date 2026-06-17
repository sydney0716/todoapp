# Current Next Steps

Last PM / Project Architect review: 2026-05-29.

## Recommended Sequence

1. Stabilize the Android local app MVP.

   Confirm tasks, subtasks, habits, calendar, settings, starter data, and trash
   behavior on the real Android phone before adding server sync. This protects
   the existing migration work from sync-related noise.

2. Finalize the sync data contract.

   Lock IDs, ownership, private/shared visibility, deleted/trash state,
   retention settings, conflict fields, and sync timing before implementing
   client/server sync deeply.

3. Implement the backend MVP on the Oracle VM.

   The current FastAPI server is still mostly a contract skeleton. The next
   backend milestone is fixed two-user auth, Postgres persistence, task/subtask
   sync, habit sync, trash retention settings, backups, and deployment
   verification.

4. Connect the Flutter app to the server.

   Add login, device registration, push/pull sync queue, shared/private item
   handling, offline retry, and visible sync error states.

5. Enable iOS, iPadOS, and macOS after Android sync works.

   Cross-platform support matters, but validating Android sync first keeps the
   first end-to-end sync milestone smaller and easier to debug.

## Should Wait

- Real-time live sync or websockets.
- More than two accounts.
- Public signup, password reset, or account recovery automation.
- Complex permissions or roles.
- App Store, TestFlight, and Play Store release work.
- Advanced collaboration features.
- Large UI redesigns beyond fixing blockers.

## Decisions Needed

- Domain name for the Oracle server, such as `todo.yourdomain.com`.
- The two fixed account names/emails.
- Default trash retention. Recommended default: `30 days`.
- Trash retention options. Recommended options: `7 days`, `30 days`,
  `90 days`, and `never auto-delete`.
- Confirm MVP conflict rule: latest edit wins by `updated_at`.
- Confirm whether habits sync in the first server MVP. Recommendation: sync
  tasks and habits together.

## Immediate Engineering Task

The next best implementation task is to finish the sync contract document and
then implement the server-side MVP. Do not start Apple platform work until the
Android app can sync correctly through the Oracle VM.
