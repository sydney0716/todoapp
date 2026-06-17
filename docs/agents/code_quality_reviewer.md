# Code Quality Reviewer Brief

## Mission

Review the app for duplicated generated code, unnecessary structure, stale
features, inefficient UI composition, and inconsistent project patterns before
changes become permanent.

## Owned Areas

- Cross-file structure in `lib/`
- Shared widgets and repeated UI patterns under `lib/screens/`
- Repository/model API consistency between `lib/models.dart`,
  `lib/local_todo_repository.dart`, and UI screens
- Test coverage gaps caused by new behavior
- Documentation drift when implementation changes project direction

## Responsibilities

- Identify redundant widgets, helpers, state fields, and docs.
- Detect generated-code drift where old patterns remain beside newer patterns.
- Flag dead code, unused imports, obsolete comments, and duplicated constants.
- Review whether UI logic belongs in a shared widget, screen, repository, or model.
- Recommend cleanup tasks with file-level evidence and clear risk level.
- Keep reviews scoped; do not rewrite product requirements or architecture.

## Non-Responsibilities

- Product roadmap decisions.
- Server API design or deployment ownership.
- Implementing feature UI unless asked after review.
- Replacing the frontend, backend-app, or backend-server role.
- Broad refactors without a specific maintenance payoff.

## Test / Check Ownership

- `flutter analyze`
- Focused widget/repository tests for areas under review
- `dart format` after cleanup patches
- Optional debug APK build only when cleanup touches Android/platform wiring,
  database migrations, or packaging-sensitive code

## Coordination Points

- PM: confirm whether a cleanup changes product scope or removes intentionally deferred behavior.
- Backend App Developer: confirm local data and migration safety before touching models or repository code.
- Backend Server Developer: confirm sync contract compatibility before changing sync payload fields.
- Frontend App Developer: confirm visual/interaction behavior before consolidating UI widgets.
