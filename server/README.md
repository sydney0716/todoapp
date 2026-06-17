# Personal Todo: Sync Backend

This is the backend synchronization server for the Personal Todo mobile application. It acts purely as a high-performance sync hub—resolving conflicts, tracking device cursors, and serving as the canonical source of truth for all shared tasks.

Because the mobile app is strictly offline-first, this backend is completely stateless from the UI's perspective. It only receives pushed operations (upserts/deletes) and provides an incremental cursor-based pull API for clients to download changes they missed while offline.

## Tech Stack

* **Framework:** Python 3 + [FastAPI](https://fastapi.tiangolo.com/)
* **Database:** PostgreSQL
* **ORM:** SQLAlchemy (with async support)
* **Auth:** Bearer tokens (JWT)
* **Deployment:** Docker & Docker Compose
* **Testing:** `pytest` with `pytest-asyncio`

## How it Works

The sync protocol revolves around two primary endpoints:

1. **`POST /sync/tasks` (Push):** The client pushes a batch of operations (e.g., "changed title", "completed subtask"). The server inspects the timestamps of the changed fields. If the client's change is newer than the server's record, it accepts the change. Otherwise, it silently rejects the outdated fields.
2. **`GET /sync/tasks` (Pull):** The client provides its last known sync cursor (an opaque string representing a database sequence). The server returns all task/subtask events that occurred after that cursor.

## Running Locally for Development

To run the server locally without Docker (useful for running tests or debugging):

1. **Set up a Python Virtual Environment:**
   ```bash
   cd server
   python3 -m venv .venv
   source .venv/bin/activate
   ```

2. **Install Dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

3. **Configure Environment:**
   Copy the example environment file and configure your credentials.
   ```bash
   cp .env.example .env
   ```
   *(Note: You will need a local PostgreSQL instance running and configured in your `.env` to start the server).*

4. **Start the Server:**
   ```bash
   uvicorn app.main:app --reload
   ```
   The API will be available at `http://localhost:8000`. You can view the automatic Swagger documentation at `http://localhost:8000/docs`.

## Running Tests

The server has a comprehensive integration test suite. Ensure your local Postgres database is running, then execute:

```bash
pytest
```

## Production Deployment

This server is designed to be deployed using Docker to a lightweight VPS. See the detailed Oracle Cloud Free Tier deployment guide in [`deploy/README_ORACLE_VM.md`](deploy/README_ORACLE_VM.md).
