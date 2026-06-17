# Agent Responsibilities

This folder contains only active role definitions. Planning docs live in
`docs/planning` so they are not counted as subagents.

## Active Roles

Use these five roles only:

| Role | Responsibility Doc |
| --- | --- |
| PM / Project Architect | [pm_project_architect.md](pm_project_architect.md) |
| Backend App Developer | [backend_app_developer.md](backend_app_developer.md) |
| Backend Server Developer | [backend_server_developer.md](backend_server_developer.md) |
| Frontend App Developer | [frontend_app_developer.md](frontend_app_developer.md) |
| Code Quality Reviewer | [code_quality_reviewer.md](code_quality_reviewer.md) |

## Role Boundaries

- PM owns product direction, feature scope, sync policy, and milestone order.
- Backend App owns Flutter local data, SQLite, migrations, sync queue, and app-side data contracts.
- Backend Server owns server APIs, auth, server database, deployment, and sync backend behavior.
- Frontend App owns visible Flutter UI, responsive layout, theme, accessibility, and interaction polish.
- Code Quality Reviewer audits generated code for duplicated structure, dead code, inefficient UI composition, and inconsistent patterns.

## Planning References

- [Required Jobs Todo List](../planning/required_jobs_todo.md)
- [Current Next Steps](../planning/next_steps.md)
- [Oracle Free Tier Backend Direction](../planning/oracle_free_tier_backend.md)
- [Approved MVP Sync Protocol](../planning/mvp_sync_protocol.md)
