# Personal Todo

**English** | [한국어](README.ko.md)

A shared to-do app for two people on Mac, Android, iOS, and the web. I built it for my partner and me because most to-do apps have either too many features or too few useful ones.

| Light mode | Dark mode | Task editor |
| :---: | :---: | :---: |
| <img src="assets/screenshots/main_light.png" width="250" alt="Light mode home" /> | <img src="assets/screenshots/main_dark.png" width="250" alt="Dark mode home" /> | <img src="assets/screenshots/add_task.png" width="250" alt="Task editor" /> |

| Android widget | Mac todo widget | Mac calendar widget |
| :---: | :---: | :---: |
| <img src="assets/screenshots/android_widget.jpeg" width="250" alt="Android widget" /> | <img src="assets/screenshots/mac_widget_todo.png" width="250" alt="Mac todo widget" /> | <img src="assets/screenshots/mac_widget_calendar.png" width="250" alt="Mac calendar widget" /> |

## Features

- **Offline-first sync**: edits save locally and upload when a connection is available.
- **Shared completion**: a task can require one person or both people to complete it.
- **Subtasks**: ordered subtasks sync together with their parent task.
- **Widgets**: Android, macOS, and iPhone widgets let you check off tasks without opening the app.
- **Reminders**: on Android and Apple devices.

## Stack

| | |
| --- | --- |
| App | Flutter, SQLite (`sqflite`), local sync queue |
| Server | FastAPI, PostgreSQL, SQLAlchemy |
| Deploy | Docker Compose, Caddy (HTTPS) |

## Requirements

| Platform | Minimum | Widgets |
| --- | --- | --- |
| Android | 8 (API 26) | Supported |
| iOS | 15 | Checkboxes require iOS 17 |
| macOS | 12 | Desktop widgets require macOS 14 |
| Web | Current Safari or Chrome | No native widgets |

## Getting started

Replace `<your-domain>` with your own hostname.

1. **Deploy the server.** You need a VPS with Docker and a domain. See the [deployment guide](server/deploy/README_ORACLE_VM.md).
2. **Build a client.** For Android:

   ```sh
   flutter build apk --dart-define=TODO_API_BASE_URL="https://<your-domain>"
   ```

   Or build the web app:

   ```sh
   bash scripts/build_web.sh
   ```

   See the deployment guide to publish `build/web/`. Native apps also accept the server address on the login screen.
3. **Log in** as `user1` or `user2` using `USER1_PASSWORD` or `USER2_PASSWORD` from `server/.env`.
4. **On iPhone/iPad**, open `https://<your-domain>/app/` in Safari, then choose Share → Add to Home Screen → Open as Web App. No weekly signing renewal is needed.

## Good to know

- Open apps check for changes every 30 seconds. Native apps request background refresh about every 2 hours; the OS may delay or skip it.
- The web app works offline after the first online load and syncs while open or on reopen. Widgets and scheduled reminders require native apps.
- The completed-task retention setting is stored on each device, so use the same value on all of the owner's devices.
- Only the owner automatically moves completed tasks to the trash. Trash is kept for 30 days.
- If Android can't use exact alarms, it falls back to inexact reminders and shows a warning in Settings.
- When a session expires, the app opens the login screen. Cached tasks and pending changes are kept.

## More docs

- [Backend](server/README.md): sync protocol, local development, and tests
- [Deployment](server/deploy/README_ORACLE_VM.md): setup, upgrades, web hosting, and backups
