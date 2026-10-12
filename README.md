# Personal Todo

[English](#personal-todo) | [한국어](#한국어)

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
* **Subtasks:** Ordered children synced with their parent task.
* **Widgets:** Native task-list widgets for Android, macOS, and iPhone. Completion actions go through the Flutter repository and its sync queue; Apple widgets also show completion immediately while saving the change.

## Architecture

The repository is structured as a monorepo containing both the mobile app and the backend server.

### 1. Mobile Client (Flutter)
The mobile app uses Flutter with a local SQLite repository and native bridges for widgets and reminders.
* **Local Storage:** Driven by `sqflite`. The `LocalTodoRepository` acts as the single source of truth for the UI.
* **Sync Queue:** Every mutation generates a JSON payload that is added to a local sync queue table.
* **State Management:** Reactive updates using `ChangeNotifier` to decouple the UI from networking logic.
* **Testing:** The client includes a Flutter test suite covering UI components, local repository state manipulation, native widget actions, and sync protocol logic.

### 2. Backend Server (Python)
The backend is a REST API that acts as the synchronization hub.
* **Framework:** `FastAPI`
* **Database:** `PostgreSQL` interacted with via `SQLAlchemy`.
* **Sync Protocol:** Clients send the fields and subtasks they changed. The server applies those mutations in transaction order and returns canonical versions. Both-person tasks merge each caller's completion separately. Incremental pulls use bounded cursor pages; snapshots preserve pending local edits.
* **Deployment:** Containerized for deployment via `docker-compose`.

## Running it for Yourself

A self-hosted backend API is required for device-to-device sync. The supplied deployment uses your Oracle VM with Postgres and Caddy for HTTPS.

### Step-by-Step Setup

1. **Deploy the Server:**
   * Create an Oracle Cloud VM (or an equivalent VPS).
   * Point a domain name to your VM's IP address.
   * SSH into your server, install Docker, and clone this repository.
   * See the deployment instructions in [`server/deploy/README_ORACLE_VM.md`](server/deploy/README_ORACLE_VM.md).
   * Configure `server/.env`, back up an existing database, and apply migrations before starting the updated API as described in that guide.

2. **Configure the App:**
   * Open the Flutter project.
   * Configure the server on the initial login screen. The default is `https://todo.example.com`.
   * Builds can supply `--dart-define=TODO_API_BASE_URL=https://todo.yourdomain.com`. Changing a saved address retains and queues local tasks for the new server and asks you to reconnect; it can copy those tasks to that server.

3. **Build and Install:**
   * Build the Android APK (`flutter build apk`) or iOS app and install it on the devices.
   * Select `user1` or `user2` and use the corresponding `USER1_PASSWORD` or `USER2_PASSWORD` configured in `server/.env`.

### Supported devices and recovery

Android requires API 26 (Android 8) or later, iPhone requires iOS 15 or later, and the Mac app requires macOS 12 or later. Desktop widgets require macOS 14. The iPhone widget shows tasks on iOS 15 and later; interactive checkboxes require iOS 17.

Edits work offline and upload after a two-second debounce. Active apps check the server every 30 seconds; the Mac checks every two hours while behind other windows or minimized, as long as it remains running and the Mac is awake. Mac widget edits still save and sync promptly. Android and iPhone request background refresh every two hours and update the widget from the resulting local data. Android requires a network connection and a battery that is not low; both mobile operating systems can delay or skip background work. Opening the app checks for changes immediately. Failed uploads retry after 30 seconds while the app can run, backing off to five minutes. A restored network connection retries pending changes. Leaving the phone app attempts to finish queued changes within the time the OS allows. An expired session automatically opens the login page for the same account, preserving cached tasks and pending changes.

Android task/subtask widget taps and iPhone/iPad widget checkboxes (iOS/iPadOS 17+) update the widget without showing the app. Each tap is saved to a durable local queue, applied by background work, and uploaded when possible. Android applies the saved completion before waiting for the server and closes the worker's Flutter engine after finishing. Widget headers and add-task controls still open the app.

Only the owner automatically moves completed tasks to trash or permanently purges shared trash. Completion retention uses the completion time rather than the last edit. Choose the same completed-task retention on that owner's phone and Mac because the setting remains local to each device. Trash has a 30-day retention window, and local removal waits for the server's purge acknowledgement.

Android restores future reminders after reboot. When exact-alarm access is unavailable, it schedules an inexact alarm and shows a warning in Settings. Apple reminder scheduling errors are also visible there. Device notification permissions and OS delivery behavior still need physical-device checks.

### Review and verification

The client changes passed 116 Flutter tests and analysis on 2026-10-12, plus native Mac and iPhone widget state checks. Signed Mac and Android release builds and an unsigned iOS release build containing the new widget were rebuilt successfully after the latest cleanup. The latest Mac release is installed. Phone installation, iPhone signing, and actual OS background scheduling still need device checks. Backend fixes passed 39 tests with PostgreSQL and lint checks on 2026-10-09. Remaining device checks are listed in the [deployment guide](server/deploy/README_ORACLE_VM.md).

## 한국어

Personal Todo는 저와 파트너가 함께 쓰기 위해 만든 할 일 앱입니다. Mac, Android, iOS에서 사용할 수 있고, 기능이 너무 많거나 너무 부족한 기존 할 일 앱의 불편함을 줄이는 데 초점을 둡니다.

이 저장소에는 Flutter 클라이언트와 Python/FastAPI 동기화 백엔드가 함께 들어 있습니다.

### 주요 기능

* **크로스 플랫폼 동기화:** Mac, Android, iOS에서 동작하며 오프라인 우선 동기화 큐, 재시도 상태, 마지막 동기화 시간을 보여줍니다.
* **공유 완료:** 작업별로 한 명만 완료하면 되는지, 두 사용자 모두 완료해야 하는지 설정할 수 있습니다.
* **하위 작업:** 순서를 유지하며 상위 작업과 함께 동기화합니다.
* **위젯:** Android, macOS, iPhone에서 네이티브 할 일 위젯을 제공합니다. 완료 동작은 Flutter 저장소와 동기화 큐를 거쳐 처리되며 Apple 위젯은 저장 중에도 완료 상태를 바로 표시합니다.

### 구조

이 저장소는 모바일 앱과 백엔드 서버를 함께 관리하는 모노레포입니다.

#### 1. 모바일 클라이언트 (Flutter)

* **로컬 저장소:** `sqflite`를 사용하며, `LocalTodoRepository`가 UI의 단일 데이터 원본 역할을 합니다.
* **동기화 큐:** 모든 변경은 JSON payload로 만들어져 로컬 sync queue 테이블에 저장됩니다.
* **상태 관리:** `ChangeNotifier` 기반의 반응형 업데이트로 UI와 네트워크 로직을 분리합니다.
* **테스트:** UI 컴포넌트, 로컬 저장소 상태 변경, 네이티브 위젯 동작, 동기화 프로토콜을 검증하는 Flutter 테스트가 포함되어 있습니다.

#### 2. 백엔드 서버 (Python)

* **프레임워크:** `FastAPI`
* **데이터베이스:** `PostgreSQL`과 `SQLAlchemy`
* **동기화 프로토콜:** 변경한 필드와 하위 작업만 서버의 트랜잭션 순서대로 반영합니다. 두 명 모두 완료해야 하는 작업은 각 사용자의 완료 상태를 따로 병합합니다. 페이지 단위 pull과 전체 snapshot 모두 대기 중인 로컬 변경을 보존합니다.
* **배포:** `docker-compose` 기반 컨테이너 배포를 지원합니다.

### 직접 실행하기

기기 간 동기화에는 자체 호스팅 백엔드 API가 필요합니다. 제공된 배포 구성은 Oracle VM에서 Postgres와 HTTPS용 Caddy를 함께 실행합니다.

#### 설정 순서

1. **서버 배포**
   * Oracle Cloud VM 또는 다른 VPS를 만듭니다.
   * 도메인을 VM의 IP 주소로 연결합니다.
   * 서버에 SSH로 접속한 뒤 Docker를 설치하고 이 저장소를 clone합니다.
   * 자세한 배포 방법은 [`server/deploy/README_ORACLE_VM.md`](server/deploy/README_ORACLE_VM.md)를 참고합니다.
   * `server/.env`를 설정하고, 기존 DB를 백업한 뒤 배포 문서의 명령으로 마이그레이션을 먼저 적용합니다.

2. **앱 설정**
   * Flutter 프로젝트를 엽니다.
   * 최초 로그인 화면에서 서버 주소를 설정합니다. 기본 주소는 `https://todo.example.com`입니다.
   * 빌드 시 `--dart-define=TODO_API_BASE_URL=https://todo.yourdomain.com`으로 기본 주소를 지정할 수 있습니다. 주소 변경 시 기존 로컬 작업을 새 서버로 전송하도록 큐에 넣고 다시 로그인합니다.

3. **빌드와 설치**
   * Android APK(`flutter build apk`) 또는 iOS 앱을 빌드해 기기에 설치합니다.
   * `user1` 또는 `user2`를 선택하고 `.env`의 `USER1_PASSWORD` 또는 `USER2_PASSWORD`로 로그인합니다.

Android 8(API 26), iOS 15, macOS 12 이상을 지원하며 Mac 데스크톱 위젯은 macOS 14 이상이 필요합니다. iPhone 위젯의 체크박스는 iOS 17 이상에서 동작하며 이전 버전에서는 앱을 열어 완료할 수 있습니다. 앱이 활성화되어 있으면 30초마다 확인하고, Mac 앱이 뒤에 있거나 최소화되어 있으면 실행 중이고 Mac이 깨어 있는 동안 2시간마다 확인합니다. Android와 iPhone은 2시간 간격의 백그라운드 새로고침을 요청하지만 운영체제가 배터리와 사용 상태에 따라 지연하거나 생략할 수 있습니다. 직접 변경한 내용은 빠르게 전송하고 앱을 열면 즉시 확인합니다. 세션이 만료되면 같은 계정의 로그인 화면을 자동으로 엽니다. 로컬 작업과 대기 중인 변경은 유지됩니다.

Android 위젯의 작업·하위 작업과 iOS/iPadOS 17 이상 위젯의 체크박스는 앱 화면을 열지 않고 위젯 상태를 변경합니다. 변경은 로컬 큐에 저장한 뒤 백그라운드에서 적용하고 가능한 때 서버로 전송합니다. Android 작업이 끝나면 백그라운드 Flutter 엔진을 종료하며 위젯 제목과 작업 추가 버튼은 앱을 엽니다.

완료 작업의 자동 정리와 공유 휴지통의 영구 삭제는 소유자만 수행합니다. 완료 보관 기간 설정은 기기별이므로 소유자의 휴대폰과 Mac에서 같은 값으로 설정하세요. 실제 기기에서 확인할 항목은 [배포 문서](server/deploy/README_ORACLE_VM.md)에 기록했습니다.
