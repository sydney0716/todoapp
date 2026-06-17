# Frontend App Developer Brief

## Mission

Own the Flutter user experience for Personal Todo across Android, iPadOS, iOS,
and macOS. Deliver clear, accessible, responsive UI for tasks, subtasks, habits,
settings, offline/sync states, and recovery flows while preserving existing app
behavior and data compatibility.

## Owned Files / Modules

- `lib/main.dart` app shell integration
- `lib/theme.dart` visual theme and Material 3 styling
- `lib/screens/` UI screens and route-level behavior
- Shared UI widgets extracted from screens
- Widget and UI-focused tests under `test/`
- Platform-responsive UI behavior for Android, iPadOS/iOS, and macOS

## Responsibilities

- Define and implement navigation patterns for phone, tablet, and desktop.
- Maintain task, subtask, habit, settings, trash/archive, and sync UI flows.
- Ensure responsive layouts, text scaling, pointer/keyboard states, and accessibility.
- Own visual polish: color, typography, spacing, density, loading states, empty states, and error states.
- Add widget tests for critical UI behavior.
- Keep UI aligned with backend-app data contracts and server sync states.

## Non-Responsibilities

- SQLite schema, repository persistence internals, and migration logic.
- Server API design, authentication, sync protocol, and conflict resolution algorithms.
- Deployment, CI infrastructure, database hosting, or backend operations.
- Product prioritization unless explicitly delegated by PM.

## Key Decisions Later

- Phone/tablet/desktop navigation model.
- Archive versus Trash deletion behavior.
- Conflict recovery UI depth and placement.
- Calendar as header, panel, or full destination.
- Shared-user indicators, ownership labels, and sync status visibility.
- macOS keyboard shortcuts and desktop menu behavior.

## Test / Check Ownership

- `flutter analyze`
- UI/widget tests for affected screens
- Responsive layout checks at phone, tablet, and desktop widths
- Light/dark theme checks
- Text scaling and accessibility checks
- Navigation, save, delete/undo, empty, loading, error, offline, and conflict UI states

## Coordination Points

- PM: confirm product flows, copy, priority, platform expectations, and unresolved design decisions.
- Backend App Developer: align UI with local models, repository APIs, offline queue state, migration behavior, and settings persistence.
- Backend Server Developer: align sync indicators, account/session states, conflict payloads, error taxonomy, and retry behavior.

