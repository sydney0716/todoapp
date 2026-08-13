# Team

Updated: 2026-08-13

Use canonical roles as durable identity. Do not store runtime agent IDs.

| Role | Owns | Current Focus | State |
| --- | --- | --- | --- |
| pm | Product scope, architecture direction, milestone order, cross-role coordination, and PM docs. Does not edit production code. | Track remaining P1 work and real Postgres migration validation. | Active |
| frontend | Flutter UI screens, theme, interaction behavior, accessibility, responsive layout, and UI/widget tests. Does not own persistence internals or server contracts. | Add sync status UI, manual-sync feedback, accessibility fixes, and responsive navigation after backend-app state shape is confirmed. | Waiting |
| backend-app | Flutter local data layer, models, SQLite repository, settings/migration, app-side sync service, and persistence tests. Does not own visible UI polish or server implementation. | Android widget sync queue behavior and any follow-up sync contract tests. | Active |
| backend-server | FastAPI routes, auth, server database, migrations, deployment, and server-side sync behavior. Does not own Flutter UI or local repository implementation. | Real Postgres migration smoke tests and any follow-up server contract tests. | Active |
| code-quality | Cross-file duplication, dead code, stale docs/config, inconsistent patterns, and unnecessary complexity. Does not make product roadmap decisions. | Clean stale docs/config after P1 sync and deployment issues are fixed. | Waiting |
