# Codex Handoff

Date: 2026-05-29

## Project Root

Open this folder as the Flutter project root:

`/Users/user/Documents/Android_apps`

Do not use:

- `/Users/user/Documents/Android_apps/app`
- `/Users/user/Documents/Android_apps/legacy_android`

Both old Android/Kotlin locations have been removed.

## Current App Status

The app is a Flutter todo app with an Android host project in `android/`.

Important app files:

- `lib/main.dart`
- `lib/screens/home_screen.dart`
- `lib/screens/task_editor_screen.dart`
- `lib/screens/habit_editor_screen.dart`
- `lib/screens/settings_screen.dart`
- `lib/local_todo_repository.dart`
- `android/app/src/main/java/com/example/personaltodo/MainActivity.java`

## Verification

Use lightweight checks for Dart-only UI changes:

```bash
dart format lib test
flutter analyze
```

Use a debug APK build when Android host, Gradle, package identity, or native
bridge code changes:

```bash
flutter build apk --debug
```

The Android package id remains `com.example.personaltodo`.
