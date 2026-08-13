# Roadmap

Updated: 2026-08-13

## Milestones

| Milestone | Outcome | State | Dependencies |
| --- | --- | --- | --- |
| Current repo audit | Find likely errors, over-engineering, stale code, and validation gaps across app and server | Complete | Specialist review reports accepted 2026-08-13 |
| Sync stabilization | App/server contracts and tests converge around the approved MVP sync protocol | Active | Backend-server and backend-app fixes |
| Release readiness | Android-first sync smoke path works before broader platform release work | Planned | Passing app/server validation |

## Current Status

- Now: Repository-wide audit completed on 2026-08-13. Core P1
  sync/deployment/data-safety fixes are implemented for app repository reads,
  bootstrap reconciliation, sync payload deltas, server LWW handling, purge
  retention, logout/device behavior, and Oracle VM migration order.
- Blocked by: No real Postgres migration smoke test was run; backend tests used
  a temp dependency target and fake DB tests.
- Next checkpoint: Fix Android widget sync queue behavior and add visible sync
  status UI, then run server migrations against a real Postgres instance.

## To-Do

- [x] **P1 · backend-server** — Replace fragile Oracle migration/startup flow with one migration path before API startup; include migrations `001` through `006`.
- [x] **P1 · backend-server + backend-app** — Fix task/subtask sync conflict semantics so stale parent edits cannot overwrite newer subtask changes and documented LWW rules are either implemented or explicitly revised.
- [x] **P1 · backend-server** — Enforce trash retention before purge and fix logout/device FK behavior so sessions can be revoked after task creation.
- [x] **P1 · backend-app + frontend** — Enforce private-owner isolation locally for active and trash task visibility.
- [x] **P1 · backend-app** — Prevent bootstrap reconciliation from deleting pending/deferred local changes.
- [ ] **P1 · backend-app/native** — Ensure Android widget mutations enqueue sync changes or route through Flutter repository behavior.
- [ ] **P1 · frontend + backend-app** — Add top-level sync status and details entry point covering pending, failed, offline, retry, and last-sync state.
- [ ] **P2 · backend-server** — Add Postgres-backed migration/auth/sync tests; fake DB tests miss FK, enum, and SQL constraint failures.
- [ ] **P2 · frontend** — Add tablet/Mac navigation coverage, improve manual-sync feedback, replace or harden custom time picker, and fix completion-control accessibility.
- [ ] **P2 · backend-app + backend-server** — Add contract tests or shared metadata for changed sync fields to prevent drift.
- [ ] **P3 · code-quality** — Clean stale docs/config and defer large file splits until sync behavior is stable.

## Recently Completed

- [x] **PM** — Reconstructed role boundaries from `docs/agents` and created this audit coordination state.
- [x] **frontend** — Completed read-only UI audit; `flutter analyze` and focused widget tests passed.
- [x] **backend-app** — Completed read-only app data/sync audit; focused Flutter tests passed.
- [x] **backend-server** — Completed read-only server audit; backend validation blocked by missing `pytest`/`ruff`.
- [x] **code-quality** — Completed repo-wide audit; `flutter analyze --no-pub` and full `flutter test` passed.
- [x] **backend-app/backend-server/code-quality** — Applied P1 remediation for sync deltas, LWW conflict handling, retention-gated purge, logout token invalidation, local private-owner filtering, snapshot safety, runtime migration guard, Oracle deploy docs, and dead enum/helper cleanup.
- [x] **validation** — `flutter analyze`, full `flutter test`, `ruff check server/app server/tests`, `python3 -m compileall server/app server/tests`, and `pytest server/tests` passed on 2026-08-13. Backend tests used temp deps from flexible `pyproject` bounds because pinned `psycopg-binary==3.2.3` is unavailable for local Python 3.14.
