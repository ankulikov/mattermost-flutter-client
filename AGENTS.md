# AGENTS.md

## Mission

Build a production-grade Mattermost client in Flutter for Android, iOS, Web,
macOS, and Windows. Preserve behavior important to Mattermost users, but do not
reproduce React Native implementation details.

## Required reading

Before changing application code, read `docs/ARCHITECTURE.md` and the closest
feature README if one exists. Treat the official Mattermost API v4 documentation
as the protocol source of truth. The existing Mattermost mobile repository may
be used to discover behavior, not as an API contract.

## Architecture boundaries

- Organize product code as vertical feature slices with `domain`, `data`, and
  `presentation` directories.
- Domain code must not import Flutter, Riverpod, Dio, Drift, platform plugins, or
  API DTOs.
- UI and controllers must not call HTTP, WebSocket, DAOs, or secure storage
  directly. They call domain use cases/repositories.
- All REST calls go through `MattermostApi`; all realtime traffic goes through a
  `WebSocketGateway`. Do not instantiate Dio outside core API wiring.
- Keep wire DTOs, database rows, and domain entities distinct; map explicitly.
- Cross-feature dependencies go through public domain contracts. Do not import
  another feature's data or presentation internals.

## Data freshness and state

- Use a network-first model for channels, posts, threads, sidebar data, and their
  pagination. Keep this data in the Riverpod state of the open screen and release
  it when the screen closes.
- On initial request failure, show an explicit retry state. During refresh or
  pagination, preserve useful data already shown and surface failures without
  replacing it with a full-screen loader.
- Do not persist messages, threads, sidebar data, or sync metadata in Drift.
  Add durable storage only when the feature has an explicit data owner, freshness
  policy, and reason for surviving process restarts.
- Scope any durable tenant-owned data and cache keys by account/server id.
- Handle pagination completeness, WebSocket sequence gaps, idempotency, retries,
  rate limits, and deletion behavior explicitly where the feature requires them.

## Async and performance

- Never perform synchronous file, database, crypto, or heavy JSON work on the UI
  isolate. Use Drift background execution and isolates for large transforms.
- Await futures or deliberately mark them unawaited with centralized error
  handling. The analyzer treats discarded futures as errors.
- Cancel superseded searches/requests. Bound concurrency, pagination, and batch
  sizes. Back off retries with jitter and honor Mattermost rate limiting.
- Use Riverpod `select` and small widgets to avoid broad rebuilds. Preserve list
  identity, scroll position, and focus during refresh.

## Adaptive UI and accessibility

- Choose layout from available width with `LayoutBuilder`/constraints, never from
  a mobile/desktop platform check.
- Support compact, medium, and expanded layouts. Keep breakpoints as shared design
  tokens and add tests on both sides of each breakpoint.
- Every workflow must support keyboard/focus behavior where relevant, semantics,
  scalable text, touch targets, light/dark themes, and localized user-facing text.
- Do not hardcode user-facing strings in widgets.

## Security and privacy

- Store access/session tokens only in `flutter_secure_storage`; never put them in
  Drift, logs, analytics, exceptions, fixtures, or screenshots.
- Redact authorization headers, cookies, message contents, and personal data from
  logs. Do not add verbose Dio body logging.
- Require explicit review for certificate pinning, custom CA handling, database
  encryption, telemetry, or any change to authentication persistence.
- Validate server URLs and render server-provided Markdown/HTML defensively.

## Dependencies and generated code

- Prefer maintained cross-platform packages over custom platform code, but check
  Android, iOS, Web, macOS, and Windows support before adding one.
- Explain each new runtime dependency in the pull request and avoid overlapping
  packages with the same responsibility.
- Keep constraints in `pubspec.yaml`; commit `pubspec.lock` for the application
  once generated. Never hand-edit generated `*.g.dart` or `*.freezed.dart` files.
- Run code generation after changing Drift tables or serializable DTOs.

## Definition of done

For each change, as applicable:

1. Format changed Dart files.
2. Run `flutter analyze` with no new warnings.
3. Run focused unit/widget tests and the full suite for cross-cutting changes.
4. Add tests for success, initial loading, refresh/loading-with-data, pagination,
   and failure states relevant to the changed feature.
5. For database changes, add a migration and migration test; never rewrite a
   released migration history.
6. For UI changes, test compact and expanded widths plus large text scale.
7. Update architecture/API notes when a boundary, policy, or capability changes.

If the local environment cannot run a required command, state that clearly in
the handoff instead of claiming verification.
