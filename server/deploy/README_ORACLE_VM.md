# Oracle Free Tier VM Deployment

Use the Oracle VM as the private sync backend for the two Personal Todo accounts. The VM should run only the API, Postgres, HTTPS reverse proxy, and backups. Flutter builds stay on your laptop.

Current server status: `/health`, fixed-account auth, refresh/logout, task bootstrap, task push, task pull, task trash restore, and retention-gated permanent delete are implemented. Trash settings and habit sync are still deferred.

## Target Layout

- `api`: FastAPI service from `server/Dockerfile`.
- `postgres`: private Postgres container, not exposed to the internet.
- `caddy`: HTTPS reverse proxy on ports `80` and `443`.
- `personaltodo_pgdata`: Docker volume containing synced data.
- `~/personal_todo_backups`: recommended backup directory on the VM.

## 1. Point A Domain To The VM

1. Copy the VM public IP from the Oracle Cloud console.
2. Create an `A` record such as `todo.yourdomain.com -> VM_PUBLIC_IP`.
3. Wait for DNS to propagate.

HTTPS needs a real domain. You can test raw connectivity with the public IP, but use a domain before connecting production app builds.

## 2. Lock Down Oracle Networking

In the VM subnet security list or network security group:

- Allow TCP `22` only from your current IP address.
- Allow TCP `80` from `0.0.0.0/0`.
- Allow TCP `443` from `0.0.0.0/0`.
- Do not open TCP `5432`; Postgres stays private inside Docker.

On the VM firewall, allow the same ports if the OS firewall is enabled.

## 3. Install Docker On The VM

SSH into the VM:

```bash
ssh opc@VM_PUBLIC_IP
```

Install Docker and the Compose plugin using the official instructions for your VM OS. On Ubuntu, the flow is:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
```

Log out and back in so the `docker` group applies, then verify:

```bash
docker version
docker compose version
```

## 4. Copy The Project To The VM

Use Git if this repo is pushed to a private remote:

```bash
git clone YOUR_PRIVATE_REPO_URL personal_todo
cd personal_todo
```

Or copy the folder from your Mac:

```bash
rsync -av --exclude '.git' /Users/user/Documents/Android_apps/ opc@VM_PUBLIC_IP:~/personal_todo/
ssh opc@VM_PUBLIC_IP
cd ~/personal_todo
```

## 5. Configure Secrets

Create `server/.env` on the VM:

```bash
cp server/.env.example server/.env
nano server/.env
```

Set real values:

```dotenv
POSTGRES_DB=personaltodo
POSTGRES_USER=personaltodo
POSTGRES_PASSWORD=use-a-long-random-password
DATABASE_URL=postgresql+psycopg://personaltodo:use-a-long-random-password@postgres:5432/personaltodo
JWT_SECRET=use-a-different-long-random-secret
ACCESS_TOKEN_MINUTES=15
REFRESH_TOKEN_DAYS=60
USER1_PASSWORD=use-a-private-account-password
USER2_PASSWORD=use-a-different-private-account-password
PERSONAL_TODO_DOMAIN=todo.yourdomain.com
```

Never commit `server/.env`.

## 6. Start The Backend

From the repo root on the VM:

```bash
docker compose --env-file server/.env -f server/deploy/docker-compose.oracle.yml up -d postgres
```

Apply the database migrations:

```bash
docker compose --env-file server/.env -f server/deploy/docker-compose.oracle.yml exec -T postgres sh -lc 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < server/migrations/001_tasks_mvp.sql
docker compose --env-file server/.env -f server/deploy/docker-compose.oracle.yml exec -T postgres sh -lc 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < server/migrations/002_task_device_id.sql
docker compose --env-file server/.env -f server/deploy/docker-compose.oracle.yml exec -T postgres sh -lc 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < server/migrations/003_refresh_token_expiry.sql
docker compose --env-file server/.env -f server/deploy/docker-compose.oracle.yml exec -T postgres sh -lc 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < server/migrations/004_sync_event_metadata.sql
docker compose --env-file server/.env -f server/deploy/docker-compose.oracle.yml exec -T postgres sh -lc 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < server/migrations/005_shared_completion.sql
docker compose --env-file server/.env -f server/deploy/docker-compose.oracle.yml exec -T postgres sh -lc 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < server/migrations/005_subtask_due_at.sql
docker compose --env-file server/.env -f server/deploy/docker-compose.oracle.yml exec -T postgres sh -lc 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < server/migrations/006_sync_event_shared_visibility.sql
```

Then start the full stack:

```bash
docker compose --env-file server/.env -f server/deploy/docker-compose.oracle.yml up -d --build
```

Check health:

```bash
curl https://todo.yourdomain.com/health
```

Expected response:

```json
{"status":"ok"}
```

## 7. Daily Operations

View status:

```bash
docker compose --env-file server/.env -f server/deploy/docker-compose.oracle.yml ps
```

View logs:

```bash
docker compose --env-file server/.env -f server/deploy/docker-compose.oracle.yml logs -f api
```

Restart after updates:

```bash
git pull
docker compose --env-file server/.env -f server/deploy/docker-compose.oracle.yml up -d --build
```

Create a backup:

```bash
server/deploy/backup_postgres_docker.sh
```

Restore backups only after stopping app writes and confirming the target database. Treat restore as a deliberate maintenance operation, not an automatic process.

## 8. Remaining Release Checks

Before treating the Android, iOS, iPadOS, and macOS apps as release-ready against this VM:

1. Run the opt-in Postgres migration/auth/task/sync smoke test against a disposable database using `TODOAPP_TEST_DATABASE_URL`.
2. Verify a clean device-to-device task sync path: login, bootstrap, local queue push, pull, trash restore, permanent delete, shared/private visibility, and Android widget completion.
3. Confirm the app API URL is set to the production domain on each device build.
4. Test install-over migration from the old Android app.
5. Decide whether trash settings and habit/habit completion sync remain deferred for this release or need server schema/API work.

## References

- Oracle Compute instances and SSH connection docs: <https://docs.oracle.com/iaas/Content/Compute/Tasks/instances.htm>
- Oracle Linux instance connection docs: <https://docs.oracle.com/iaas/Content/Compute/Tasks/connect-to-linux-instance.htm>
- Oracle network security rules docs: <https://docs.oracle.com/iaas/Content/Network/Concepts/securityrules.htm>
- Docker Engine install docs: <https://docs.docker.com/engine/install/>
