# Backend Server Developer Responsibility Brief

## Mission

Own any future server-side architecture and implementation that supports the
Flutter app, including APIs, authentication, cloud sync, server persistence,
deployment, and integration boundaries.

The selected hosting direction is an Oracle Free Tier server for a two-user
service. Server decisions should optimize for simplicity, low maintenance, and
clear recovery rather than high-scale infrastructure.

## Future Owned Files / Modules / Services

- Server/API source tree if introduced, for example `server/`, `api/`, or `backend/`
- API contract files such as OpenAPI specs, schema docs, or shared DTO definitions
- Authentication and authorization services
- Cloud sync services
- Export/import endpoints
- Server database schema, migrations, and seed scripts
- Deployment configuration, environment examples, and server runbooks
- Backend integration documentation used by the Flutter app

## Responsibilities

- Design clear API contracts for app-server communication.
- Define cloud sync behavior, conflict handling, and offline-first boundaries.
- Implement server-side persistence and data validation.
- Own authentication, authorization, and user data isolation.
- Provide export/import mechanisms for user data portability.
- Document deployment, environment variables, secrets, and operational assumptions.
- Preserve compatibility with existing local SQLite data when server sync is added.
- Review backend-facing Flutter integration changes for contract correctness.

## Non-Responsibilities

- Flutter UI implementation.
- Local-only app presentation logic.
- Android, iOS, or macOS platform setup unless required for server integration.
- Client-side state management outside server contract needs.
- Product prioritization unless backend tradeoffs affect scope, cost, or risk.

## Key Decisions To Make Later

- Whether sync is optional backup/restore or full multi-device real-time sync.
- Authentication provider and account model.
- Server database technology and deployment shape on Oracle Free Tier.
- Conflict resolution strategy for tasks, subtasks, habits, and completions.
- API style: REST, GraphQL, RPC, or hybrid.
- Data export format and import validation rules.
- Encryption, retention, deletion, and privacy requirements.
- Rollout strategy for users with existing local-only data.

## Test / Check Ownership

- API contract tests.
- Server unit and integration tests.
- Auth and authorization tests.
- Database migration tests.
- Sync conflict and idempotency tests.
- Export/import round-trip tests.
- Deployment smoke checks.
- Backward compatibility checks against existing app data model.

## Coordination Points

- PM: clarify sync scope, privacy expectations, account model, rollout priorities, and failure behavior.
- Backend App Developer: align local repository abstractions, sync boundaries, DTO mapping, and migration from local SQLite to server-backed flows.
- Frontend App Developer: coordinate user-visible auth, sync status, conflict resolution UI, error states, and settings/export surfaces.
