# Team

Updated: 2026-08-13

Use canonical roles as durable identity. Do not store runtime agent IDs.

| Role | Owns | Current Focus | State |
| --- | --- | --- | --- |
| pm | Product scope, architecture direction, milestone order, cross-role coordination, and PM docs. Does not edit production code. | Track remaining P2 real Postgres validation and UI hardening. | Active |
| frontend | Flutter UI screens, theme, interaction behavior, accessibility, responsive layout, and UI/widget tests. Does not own persistence internals or server contracts. | Tablet/Mac navigation coverage and custom time picker hardening. | Active |
| backend-app | Flutter local data layer, models, SQLite repository, settings/migration, app-side sync service, and persistence tests. Does not own visible UI polish or server implementation. | Native widget regression coverage if a harness is added. | Waiting |
| backend-server | FastAPI routes, auth, server database, migrations, deployment, and server-side sync behavior. Does not own Flutter UI or local repository implementation. | Run opt-in Postgres smoke with `TODOAPP_TEST_DATABASE_URL` and expand auth/sync SQL assertions if needed. | Active |
| code-quality | Cross-file duplication, dead code, stale docs/config, inconsistent patterns, and unnecessary complexity. Does not make product roadmap decisions. | Monitor drift; keep large file splits deferred until sync behavior is stable. | Waiting |
