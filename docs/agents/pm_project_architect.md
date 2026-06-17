# PM / Project Architect Responsibility Brief

## Mission

Define the product direction and system architecture for the Flutter todo/habit
app across Android, iOS/iPadOS, and macOS, including the path from local-first
storage to two-user server sync.

## Owned Docs / Decisions

- Product vision and scope
- Platform support plan
- Feature roadmap
- Sync and data lifecycle policy
- Delete, archive, and trash policy
- Privacy and security assumptions
- Cross-team architecture decisions
- Release readiness criteria

## Responsibilities

- Maintain the big-picture product and architecture brief.
- Define what services and functions the app should provide.
- Decide staged milestones from local Android app to cross-platform synced app.
- Specify high-level data ownership, sync behavior, conflict rules, and retention policy.
- Clarify user flows before implementation starts.
- Keep backend-app, backend-server, and frontend work aligned.
- Identify open decisions and force resolution before they block implementation.

## Non-Responsibilities

- Writing Flutter UI code.
- Implementing SQLite repositories or migrations.
- Building server APIs, databases, auth, or deployment infrastructure.
- Creating detailed widget designs or visual theme systems.
- Owning low-level test implementation.

## Key Decisions To Make Later

- Domain name for the Oracle server, such as `todo.yourdomain.com`.
- The two fixed account names/emails.
- Default Trash retention. Recommended default: `30 days`.
- Trash retention options. Recommended options: `7 days`, `30 days`,
  `90 days`, and `never auto-delete`.
- Confirm whether habits sync in the first server MVP. Recommendation: sync
  tasks and habits together.
- Detailed rules for private item visibility and conversion between private/shared.
- Which non-display settings, if any, should sync across devices.
- Conflict handling policy beyond MVP last-write-wins.
- Whether macOS launches with a desktop-specific layout.
- Backup/export requirements.
- Release order: Android first vs simultaneous Android, iOS/iPadOS, and macOS.

## Validation Ownership

- Confirms product requirements are covered before implementation.
- Reviews whether sync behavior matches the agreed lifecycle protocol.
- Owns acceptance criteria for cross-platform readiness.
- Confirms Oracle Free Tier constraints remain acceptable for a two-user service.
- Verifies that roadmap stages are complete at a product level.
- Ensures privacy and security assumptions are documented and respected.

## Coordination Points

- Backend App Developer: local database schema, migration constraints, sync queue behavior, offline-first assumptions.
- Backend Server Developer: API boundaries, auth model, server data model, sync protocol, retention policy enforcement.
- Frontend App Developer: platform-specific UX expectations, responsive layout priorities, settings surfaces, sync/trash/archive user flows.
