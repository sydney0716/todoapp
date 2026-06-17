# Required Jobs Todo List

This todo list is organized by agent ownership. It reflects the current project
state: Flutter migration is in place, the legacy Kotlin project has been
removed, and the target product is Android, iOS/iPadOS, and macOS with two-user
server sync. The selected backend hosting direction is an Oracle Free Tier
server with a custom API and Postgres.

## PM / Project Architect

### Phase 0: Current-State Alignment

- [ ] Confirm root project is Flutter-first.
- [x] Confirm legacy Kotlin source has been removed from the repo.
- [ ] Confirm Android package id remains `com.example.personaltodo`.
- [ ] Confirm local SQLite and settings migration goals are documented.

Acceptance criteria:
- Android Flutter app builds and runs.
- Migration risks and known gaps are listed.
- Legacy rollback depends on git history, not an in-repo Kotlin archive.

### Phase 1: Product Scope Definition

- [ ] Define required task, subtask, habit, completion, settings, undo, archive, and trash behavior.
- [ ] Separate MVP features from later enhancements.
- [ ] Decide whether starter content remains in production.
- [ ] Define launch support for Android, iOS/iPadOS, and macOS.
- [ ] Decide whether macOS needs a desktop-specific layout at MVP.
- [ ] Define platform-specific acceptance checks.

Acceptance criteria:
- MVP feature list is approved.
- Deferred features are explicitly tracked.
- Supported platforms and release order are documented.

### Phase 2: Sync Product Protocol

- [x] Decide data model: private items plus shared items.
- [x] Define account model: two fixed human accounts with multiple devices.
- [x] Define display settings policy: theme/time format remain per-device.
- [x] Choose MVP conflict policy: local-first with `updated_at`/`version` and last-write-wins.
- [ ] Define local save behavior, remote save behavior, offline behavior, and sync timing.
- [ ] Define archive, Trashcan, restore, user-selectable Trash retention, and permanent deletion rules.
- [ ] Write scenario-level acceptance cases for two devices and two users.

Acceptance criteria:
- Data lifecycle protocol covers create, update, complete, archive, delete, restore, and permanent delete.
- Offline and reconnect behavior is documented.
- Sync scenarios are testable without ambiguous product judgment.

### Phase 3: Server Strategy

- [x] Select Oracle Free Tier as the backend hosting direction for the two-user service.
- [x] Select custom API plus Postgres as the backend stack direction.
- [ ] Define the Oracle Free Tier deployment shape: app runtime, Postgres, reverse proxy, backups, and monitoring.
- [x] Define auth scope: fixed two accounts, each usable from multiple devices.
- [ ] Define deployment and maintenance expectations.
- [ ] Review and approve the high-level sync API contract.
- [ ] Confirm server responsibilities vs app responsibilities.
- [ ] Confirm retention and permanent-delete enforcement.

Acceptance criteria:
- Oracle Free Tier deployment assumptions are documented.
- Hosting, auth, database, and backup assumptions are documented.
- API responsibilities match product lifecycle rules.

### Phase 4: Cross-Platform Product Readiness

- [ ] Approve phone, iPad, iPhone, and macOS navigation/layout expectations.
- [ ] Confirm theme behavior and settings surfaces.
- [ ] Confirm sync, offline, trash, and error states are visible where needed.
- [ ] Define release checklist for Android, iOS/iPadOS, and macOS.
- [ ] Include migration, sync, offline, privacy, and recovery checks.
- [ ] Define manual validation flow for two real users/devices.

Acceptance criteria:
- Frontend plan supports all target platforms.
- Required states are represented in UI.
- Release checklist is actionable and covers data-loss risks.

### Phase 5: Governance During Build

- [ ] Review new feature requests against MVP scope.
- [ ] Decide whether new requests are included, deferred, or rejected.
- [ ] Keep roadmap updated.
- [ ] Review completed milestones against acceptance criteria.
- [ ] Separate release blockers from nice-to-have improvements.

## Backend App Developer

### Phase 0: Migration Stabilization

- [ ] Verify Room-compatible SQLite schema for `tasks`, `subtasks`, `habits`, and `habit_completions`.
- [ ] Add/maintain fixture-based tests using a legacy-shaped database.
- [ ] Confirm `personal_todo.db` path behavior on Android package upgrade.
- [ ] Keep starter seeding idempotent for fresh installs and migrated users.
- [ ] Harden legacy SharedPreferences migration retry/fallback behavior.

Acceptance criteria:
- Existing Kotlin app data opens in Flutter without schema errors.
- Starter content appears once on fresh install and never duplicates migrated user data.
- `flutter analyze`, `flutter test`, and Android debug build pass.

### Phase 1: Cross-Platform Local Persistence

- [ ] Validate sqflite behavior on iOS/iPadOS/macOS.
- [ ] Confirm database path, file permissions, and app sandbox behavior per platform.
- [ ] Ensure Android-only native settings migration no-ops cleanly on iOS/macOS.
- [ ] Add platform-aware persistence smoke tests where feasible.
- [ ] Document platform differences that affect data backup/restore.

Acceptance criteria:
- App launches and reads/writes tasks/habits on Android, iOS/iPadOS, and macOS.
- No Android MethodChannel errors on iOS/macOS.
- Local database survives app restart on each target platform.

### Phase 2: Domain Model Sync Readiness

- [ ] Add sync-ready fields if needed: stable IDs, timestamps, dirty state, deleted state, version/revision metadata.
- [ ] Define local conflict-safe repository operations.
- [ ] Separate user-visible deletion from permanent local purge if sync requires tombstones.
- [ ] Preserve backward migration from current local-only schema.
- [ ] Add tests for create/update/delete ordering and timestamp behavior.

Acceptance criteria:
- Local data can represent unsynced, synced, updated, and deleted records.
- Existing local databases migrate forward without data loss.
- Repository API exposes sync metadata without leaking storage details to UI.

### Phase 3: Two-User Server Sync Integration

- [ ] Implement app-side sync repository/service.
- [ ] Map local records to server DTOs and back.
- [ ] Support two-user shared data scope.
- [ ] Handle pull, push, retry, offline queue, and conflict resolution.
- [ ] Protect local data from partial sync failures with transactional updates.
- [ ] Add sync status reporting for frontend consumption.

Acceptance criteria:
- Two users can share tasks/habits through the server.
- Offline changes sync after reconnect.
- Conflicts resolve according to agreed product rules.
- Failed sync does not corrupt local SQLite data.

### Phase 4: Data Quality, Backup, And Observability

- [ ] Add lightweight app-side diagnostics for migration and sync failures.
- [ ] Add database integrity checks for startup or debug builds.
- [ ] Define safe recovery behavior for malformed local rows.
- [ ] Confirm backup/restore expectations per platform.
- [ ] Keep persistence errors actionable for frontend error states.

## Backend Server Developer

### Phase 0: Discovery / Constraints

- [ ] Confirm sync product model: exactly two users, shared workspace, or two independent accounts.
- [ ] Review current Flutter local schema: `tasks`, `subtasks`, `habits`, `habit_completions`.
- [ ] Define supported clients: Android, iOS/iPadOS, macOS.
- [ ] Document Oracle Free Tier server constraints and operational assumptions for a two-user service.

Acceptance criteria:
- Documented user/account model and data ownership rules.
- Server data model maps every local entity without data loss.
- API assumptions do not depend on Android-only behavior.
- Server architecture is realistic for a single small Oracle Free Tier deployment.

### Phase 1: API And Data Contract

- [ ] Design server API contract for auth, sync, export, import, and health checks.
- [ ] Define canonical IDs, timestamps, deletion markers, and conflict fields.
- [ ] Specify sync protocol: pull, push, full snapshot, delta sync, or hybrid.
- [ ] Provide request/response examples for first sync, normal sync, and conflict cases.

Acceptance criteria:
- API contract is reviewed by backend-app and frontend-app.
- Contract supports create/update/delete across two devices without duplicate records.

### Phase 2: Auth And Access Control

- [ ] Choose authentication approach for two-user sync.
- [ ] Define authorization rules for shared data access.
- [ ] Define account recovery, logout, and token revocation behavior.

Acceptance criteria:
- Login/session/token lifecycle is documented.
- Shared workspace access is explicit.
- Failure and re-login flows are documented for Flutter clients.

### Phase 3: Server Persistence

- [ ] Choose server database and migration tool for Oracle Free Tier.
- [ ] Create migration plan from local-only app data to server records.
- [ ] Define backup, retention, and deletion policy.

Acceptance criteria:
- Schema supports tasks, subtasks, habits, habit completions, users, workspaces, and sync metadata.
- Existing Android local data can be uploaded once without duplication.

### Phase 4: Sync Implementation

- [ ] Implement sync endpoints with idempotent writes.
- [ ] Implement conflict detection and resolution metadata.
- [ ] Implement tombstone/deletion handling.
- [ ] Implement sync status/error responses.

Acceptance criteria:
- Repeated client requests do not create duplicate records.
- Concurrent edits from two clients resolve predictably and are test-covered.
- Deletes propagate to Android, iOS/iPadOS, and macOS clients.
- Clients can distinguish auth failure, validation error, conflict, retryable server error, and offline state.

### Phase 5: Export / Import

- [ ] Define export format for all user data.
- [ ] Implement import validation and dry-run behavior.
- [ ] Add round-trip export/import tests.

Acceptance criteria:
- Export includes tasks, subtasks, habits, completions, and required sync metadata.
- Invalid imports fail safely without partial corruption.
- Exported data can be imported into a clean account with equivalent records.

### Phase 6: Deployment / Operations

- [x] Use Oracle Free Tier as the hosting target.
- [ ] Define Oracle Free Tier deployment flow.
- [ ] Define environment variables and secrets handling.
- [ ] Add health check and basic observability.
- [ ] Write backend runbook.

Acceptance criteria:
- Dev/staging/prod setup is documented.
- No secrets are required in the repo.
- Docs explain local run, test, deploy, rollback, and data migration checks.

### Phase 7: Test Ownership

- [ ] Add API contract tests.
- [ ] Add auth and authorization tests.
- [ ] Add database migration tests.
- [ ] Add sync integration tests for two users and multiple devices.
- [ ] Add import/export round-trip tests.

## Frontend App Developer

### Phase 0: Baseline UI Audit

- [ ] Audit current screens: Home, Task Editor, Habit Editor, Settings.
- [ ] Document current UI gaps for iPhone, tablet, iPadOS, macOS, sync, archive/trash, and conflict states.
- [ ] Identify reusable widgets to extract from `home_screen.dart`.

Acceptance criteria:
- Current UI behavior is understood and mapped.
- No known critical layout overflow at standard phone sizes.
- UI gaps are tracked before feature work starts.

### Phase 1: Responsive Navigation Foundation

- [ ] Define adaptive navigation:
  - Phone: tab/header plus contextual FAB.
  - iPad/tablet: `NavigationRail` plus list/detail.
  - macOS: sidebar plus list/detail/editor.
- [ ] Replace fixed-height calendar/header assumptions with adaptive layout rules.
- [ ] Add responsive breakpoints and shared layout primitives.

Acceptance criteria:
- App is usable at phone, tablet, and desktop widths.
- No primary action is hidden or clipped.
- Navigation works with touch, pointer, keyboard, and back behavior.

### Phase 2: Visual Theme System

- [ ] Refine Material 3 light/dark themes for Personal Todo.
- [ ] Standardize spacing, shape, typography, row density, and action states.
- [ ] Add theme treatment for sync, warning, conflict, archive/trash, and offline states.

Acceptance criteria:
- Light and dark themes pass contrast checks.
- UI does not rely on color alone for status.
- Theme works consistently across Android, iOS/iPadOS, and macOS sizes.

### Phase 3: Task / Subtask UI Completion

- [ ] Improve task list row metadata layout for small and large screens.
- [ ] Add task detail presentation for tablet/desktop.
- [ ] Improve subtask editing, quick-add, completion, and progress display.
- [ ] Add accessible alternatives for swipe delete.

Acceptance criteria:
- Tasks and subtasks can be created, edited, completed, deleted, and restored through accessible UI.
- Tablet/desktop can show list and selected task detail together.
- Widget tests cover save, validation, completion, delete/undo, and subtask display.

### Phase 4: Habit UI Completion

- [ ] Improve habit list and detail layouts.
- [ ] Add today completion state, recent activity/streak-ready display, and category metadata.
- [ ] Prepare habit UI for synced completion dates from another user.

Acceptance criteria:
- Habits can be created, edited, completed for today, deleted, and restored through accessible UI.
- Completion state is clear without relying only on color.
- Widget tests cover completion toggle, filtering, empty states, and editor validation.

### Phase 5: Sync / Offline UI

- [ ] Add top-level sync indicators: synced, syncing, offline, failed, needs attention.
- [ ] Add non-blocking offline banner and retry affordance.
- [ ] Add per-item pending/conflict indicators only where useful.
- [ ] Add settings section for account, sync status, last synced time, and manual retry.

Acceptance criteria:
- User can tell whether data is local-only, syncing, synced, failed, or conflicted.
- Offline use remains functional.
- Sync failures expose retry and readable error messages.

### Phase 6: Archive / Trash UI

- [ ] Add Archive/Trash navigation destination.
- [ ] Add restore and delete-permanently actions.
- [ ] Add multi-select support for tablet/desktop.
- [ ] Define delete flow from task/habit rows.

Acceptance criteria:
- Deleted/archived items are recoverable.
- Permanent delete is clearly distinguished and confirmed.
- Undo and restore flows work across phone/tablet/desktop.

### Phase 7: Conflict Recovery UI

- [ ] Add conflict queue or inline conflict entry point.
- [ ] Build field-level comparison UI: mine, other user, timestamp.
- [ ] Provide actions: keep mine, keep theirs, merge manually.
- [ ] Ensure subtasks and habit completion dates are not silently lost.

Acceptance criteria:
- Conflicts are visible and recoverable.
- User can resolve conflicts without data loss.
- Conflict UI is testable with mocked payloads.

### Phase 8: Platform Polish

- [ ] Add keyboard shortcuts for new, save, search, delete/archive, undo, sync.
- [ ] Add pointer hover/focus states and context menus.
- [ ] Validate safe areas, window resizing, split view, and desktop density.
- [ ] Review app labels, icons, and platform-specific navigation expectations.

Acceptance criteria:
- App feels native enough on Android, iOS/iPadOS, and macOS.
- Keyboard and pointer workflows are usable.
- No layout breakage during window resizing or iPad split view.

### Phase 9: UI Test Coverage

- [ ] Add widget tests for each changed screen.
- [ ] Add golden or screenshot-style checks if visual churn becomes risky.
- [ ] Add responsive layout tests for phone/tablet/desktop widths.
- [ ] Add accessibility checks for semantics, text scaling, and tap targets.

Acceptance criteria:
- `flutter analyze` passes.
- `flutter test` passes.
- Critical UI flows have widget coverage.
- New UI work includes relevant responsive and accessibility checks.
