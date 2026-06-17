# Flutter Migration

This repository was originally a Kotlin Android app using Jetpack Compose, Room, MVVM, and Material 3. It is now structured as a Flutter app root.

The active Flutter app lives in:

- `pubspec.yaml`
- `lib/`
- `android/`

The archived Kotlin app and stale root `app/` Android build output have been removed. The active Android host project is only `android/`.

## Ported Features

- Task and habit tabs
- Weekly and expandable monthly calendar header
- Local SQLite persistence using the same `personal_todo.db` name and table schema
- Starter tasks and habits
- Add, edit, complete, uncomplete, delete, and undo for tasks
- Subtasks on tasks
- Add, edit, delete, and daily completion for habits
- Task sorting by due date, title, and last modified
- Settings for theme, time format, and completed-item visibility
- Native Java migration bridge for the old `personal_todo_preferences` SharedPreferences file

## Android Studio

Open this folder as the Flutter project root:

```text
/Users/hoyoungchung/Documents/Android_apps
```

Then open `lib/main.dart` and run it on an emulator or Android device.

## Local Setup

Flutter is installed locally at `/opt/homebrew/share/flutter`. The local Android Gradle config is ignored by git; if this project is opened on another machine, set the SDK paths in `android/local.properties`:

```properties
sdk.dir=/Users/hoyoungchung/Library/Android/sdk
flutter.sdk=/absolute/path/to/flutter
```

Then run:

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
flutter run
```

The Android package id remains `com.example.personaltodo`, so an app update can keep the existing `personal_todo.db` database on-device.
