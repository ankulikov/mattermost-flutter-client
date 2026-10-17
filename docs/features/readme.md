# Architecture and feature guide

Mattermost Flutter is a network-first client for Android, iOS, Web, macOS, and
Windows. This directory describes the architecture shared by the application
and the behavior owned by each feature.

## Design priorities

Fresh server state takes priority over offline message history. Channels,
posts, threads, search results, the sidebar, and Inbox snapshots live in
Riverpod state. Route-local workflows release their state when they close.
Inbox is app-owned for the signed-in session: its first complete snapshot is
kept in memory and reconciled after realtime recovery instead of being fetched
again whenever its destination is opened.

The UI remains useful during background work. An initial failure replaces the
empty loading state with an explicit retry action. Refresh, pagination, and
mutations preserve content already on screen and report failures without
resetting the whole view.

Layouts follow available width instead of operating-system checks. Widths below
700 px use stacked content and bottom navigation. Widths from 700 px through
1119 px use a navigation rail. At 1120 px and above, the shell can show the
navigation rail, channel sidebar, and content together. A content pane needs at
least 800 px before it adds a 380 px side thread.

## Architecture

```text
app: bootstrap, router, theme, localization
  |
  +--> presentation: widgets, controllers, volatile view state
  |         |
  |         v
  |      domain: entities, policies, use cases, repository contracts
  |         ^
  |         |
  +--> data/providers: dependency wiring
            |
            v
         data: API DTOs, repositories, WebSocket, Drift, secure storage
            |
            +--> Mattermost API v4
            +--> account-scoped durable data
```

Product dependencies point inward: `presentation -> domain <- data`. Domain
code does not import Flutter, Riverpod, Dio, Drift, platform plugins, or wire
DTOs. Presentation code calls domain repositories and use cases; it does not
call HTTP, WebSocket, DAOs, or secure storage. Data implementations map DTOs and
database rows to domain entities explicitly.

New product areas use vertical slices under `lib/src/features/<feature>/` with
`domain`, `data`, and `presentation` directories. Shared, established message
and navigation code remains under the root `domain`, `data`, and `ui`
directories until it moves behind a feature contract. A feature may depend on
another feature only through a public domain interface.

All REST calls pass through `MattermostApi`. The active account owns one
closable API client and one `WebSocketGateway`. Feature repositories receive an
authenticated API instance but never receive the access token. Analyzer import
rules in `analysis_options.yaml` enforce the main boundaries.

The app composition root owns the active `ThemeData` through a Riverpod
notifier. Widgets read inherited theme values with `Theme.of(context)`; they do
not depend on theme-selection state or construct application themes locally.
The current choices are the Mattermost light and dark themes, with light as the
safe default.

## State and data ownership

Initial asynchronous state uses `AsyncValue`. Work performed after useful data
exists uses typed `OperationStatus` values: `idle`, `inProgress`, or `failed`.
Independent operations, such as refresh and pagination, keep independent
statuses so one cannot overwrite the other.

Drift stores only data with an owner, a freshness policy, and a reason to
survive process restarts. Current durable data includes account-scoped user
profiles, user preferences, recent emoji, and the expiring user-group
membership projection used by Inbox classification. Inbox also stores only its
New and Postponed counts so navigation and tab badges are available while the
first snapshot loads.
Messages, threads, sidebar snapshots, pagination cursors, and realtime sync
metadata are not stored in Drift.

Native database work runs in a background Drift isolate. Web uses Drift WASM
with a worker. Tokens stay in `flutter_secure_storage` and are never written to
Drift, logs, analytics, fixtures, or screenshots.

## Technology

| Area | Choice |
| --- | --- |
| Application | Flutter and Dart |
| State and dependency wiring | Riverpod |
| Navigation | `go_router` |
| REST | Dio behind `MattermostApi` |
| Realtime | `web_socket_channel` behind `WebSocketGateway` |
| Durable data | Drift and SQLite, scoped by account/server ID |
| Credentials | `flutter_secure_storage` |
| Markdown | `flutter_markdown_plus`, `flutter_math_fork`, and `highlight` |
| External links | `url_launcher` |
| Generated DTO/database code | `json_serializable`, `drift_dev`, and `build_runner` |

## Feature documents

- [Authentication and sessions](authentication.md)
- [Channels and sidebar](channels-and-sidebar.md)
- [Posts and permalinks](posts-and-permalinks.md)
- [Threads](threads.md)
- [Inbox and Postponed](inbox.md)
- [Message search](search.md)
- [Message composer](message-composer.md)
- [Markdown rendering](markdown.md)
- [Mentions, reactions, and emoji](mentions-and-emoji.md)
- [Profiles and statuses](profiles-and-statuses.md)
- [User preferences](preferences.md)
- [Android app updates](updates.md)
- [Attachments and interactive messages](attachments-and-actions.md)

Operational release details remain in [the release guide](../RELEASES.md).

## Cross-cutting requirements

Every workflow supports keyboard and focus behavior where relevant, semantic
labels, scalable text, minimum touch targets, localized user-facing strings,
and light and dark themes. Pointer behavior follows the actual
`PointerDeviceKind`; it is not inferred from the platform.

Requests are cancelable when a screen closes or a newer request supersedes
them. Pagination, batch requests, retries, and background work have explicit
bounds. Reconnect retries use backoff with jitter and respect Mattermost rate
limits. Every future is awaited or deliberately routed through centralized
error handling.

Server URLs are validated. Server-provided Markdown, links, images, attachment
data, and navigation targets are treated as untrusted input. Diagnostics redact
authorization headers, cookies, message bodies, and personal data.

## Verification

Changes must keep `dart analyze` and `flutter analyze` clean. Run focused tests
for the affected feature and the full suite for changes to shared API,
realtime, routing, database, or message infrastructure. UI work covers widths
on both sides of each relevant breakpoint and a large text scale. Database
changes require generated code, a migration, and a migration test.
