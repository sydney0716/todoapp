# Personal Todo

This is a to-do app for me and my partner with Mac, Android, and iOS compatibility. I made this because some to-do apps have too many functions, and some to-do apps have no useful functions.

This repository contains both the Flutter client and the Python/FastAPI sync backend.

| Light Mode Home | Dark Mode Home | Task Editor |
| :---: | :---: | :---: |
| <img src="assets/screenshots/main_light.png" width="250" alt="Light Mode Home" /> | <img src="assets/screenshots/main_dark.png" width="250" alt="Dark Mode Home" /> | <img src="assets/screenshots/add_task.png" width="250" alt="Task Editor" /> |

| Android Widget | Mac Desktop Todo Widget | Mac Desktop Calendar Widget |
| :---: | :---: | :---: |
| <img src="assets/screenshots/android_widget.jpeg" width="250" alt="Android Widget" /> | <img src="assets/screenshots/mac_widget_todo.png" width="250" alt="Mac Widget Todo" /> | <img src="assets/screenshots/mac_widget_calendar.png" width="250" alt="Mac Widget Calendar" /> |

## Key Features

* **Cross-Platform Sync:** Runs on Mac, Android, and iOS with an offline-first sync queue, retry state, and last-sync visibility.
* **Shared Completions:** Task models can be configured to require completion by either one user or both users.
* **Subtasks & Aggregates:** Complex data structures that sync atomically.
* **Widgets:** Native Android and macOS widgets integrated via Method Channels; Android widget completion actions route through the Flutter repository so sync metadata stays consistent.

## Architecture

The repository is structured as a monorepo containing both the mobile app and the backend server.

### 1. Mobile Client (Flutter)
The mobile app is built with Flutter using Clean Architecture principles.
* **Local Storage:** Driven by `sqflite`. The `LocalTodoRepository` acts as the single source of truth for the UI.
* **Sync Queue:** Every mutation generates a JSON payload that is added to a local sync queue table.
* **State Management:** Reactive updates using `ChangeNotifier` to decouple the UI from networking logic.
* **Testing:** The client includes a Flutter test suite covering UI components, local repository state manipulation, native widget actions, and sync protocol logic.

### 2. Backend Server (Python)
The backend is a REST API that acts as the synchronization hub.
* **Framework:** `FastAPI`
* **Database:** `PostgreSQL` interacted with via `SQLAlchemy`.
* **Sync Protocol:** The server resolves conflicts on a per-field basis using timestamps, accepting pushed queues and providing an incremental cursor-based pull API.
* **Deployment:** Containerized for deployment via `docker-compose`.

## Running it for Yourself

This app is fully functional and can be deployed for personal use. A self-hosted backend API is required.

The **Oracle Cloud Free Tier** provides an "Always Free" Linux VM capable of running the backend and Postgres database for two users.

### Step-by-Step Setup

1. **Deploy the Server:**
   * Create an Oracle Cloud VM (or an equivalent VPS).
   * Point a domain name to your VM's IP address.
   * SSH into your server, install Docker, and clone this repository.
   * See the deployment instructions in [`server/deploy/README_ORACLE_VM.md`](server/deploy/README_ORACLE_VM.md).
   * Copy `server/.env.example` to `server/.env`, configure your passwords, and run `docker compose up -d`.

2. **Configure the App:**
   * Open the Flutter project.
   * Update the API Base URL in the app's settings to point to your domain.

3. **Build and Install:**
   * Build the Android APK (`flutter build apk`) or iOS app and install it on the devices.
   * Log in using the `USER_PASSWORD` and `PARTNER_PASSWORD` configured in your `.env` file.
