# Backend App Developer Responsibility Brief

## Mission

Own the Flutter app's local data and migration layer so existing Android users
keep their data, new users get correct starter content, and app-domain behavior
remains reliable across releases.

## Owned Files / Modules

- `lib/local_todo_repository.dart`
- `lib/models.dart`
- `lib/settings_controller.dart`
- `lib/native_settings_migration.dart`
- `lib/starter_content_seeder.dart`
- App-side persistence and migration tests under `test/`
- Android native settings bridge when it affects app data migration:
  - `android/app/src/main/kotlin/com/hoyoungchung/personaltodo/MainActivity.kt`

## Responsibilities

- Maintain SQLite/sqflite persistence behavior.
- Preserve compatibility with the legacy Room database:
  - `tasks`
  - `subtasks`
  - `habits`
  - `habit_completions`
- Keep the database name and package-id migration assumptions intact.
- Own local repository APIs used by the UI.
- Ensure starter content seeding is idempotent.
- Own app settings migration from legacy Android SharedPreferences.
- Validate fallback behavior for missing, malformed, or partially migrated legacy data.
- Keep app-domain models stable and explicit.

## Non-Responsibilities

- Visual UI implementation and layout polish.
- Flutter widget composition outside data-driven behavior contracts.
- Backend server APIs, authentication, sync, or cloud storage.
- Product prioritization and feature scoping.
- App store metadata, signing, release operations, and platform setup except where they affect persistence.

## Key Decisions To Make Later

- Whether to introduce formal SQLite migrations beyond the current Room v3-compatible schema.
- Whether to add cloud sync and how local IDs map to remote IDs.
- Whether deleted/trash behavior should become persisted state or remain UI-only.
- Whether starter content versioning should support future content upgrades for existing users.
- Whether macOS/iOS support needs separate storage validation or platform-specific migration paths.

## Test / Check Ownership

- `flutter analyze` for owned code.
- Repository CRUD tests for tasks, subtasks, habits, and completions.
- SQLite schema compatibility tests against Room-shaped databases.
- Starter seeding idempotence tests.
- Settings migration tests for success, retry, malformed values, and no-op platforms.
- Debug APK smoke validation when persistence behavior changes.

## Coordination Points

- PM: confirm data retention requirements, migration risk tolerance, starter content behavior, and future sync expectations.
- Backend Server Developer: align local model fields, IDs, timestamps, deletion semantics, and future sync conflict rules.
- Frontend App Developer: maintain stable repository contracts, notify before changing model fields or async behavior, and support UI states for loading, failure, undo, and empty data.

