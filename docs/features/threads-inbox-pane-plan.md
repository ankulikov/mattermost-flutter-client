# Threads view in the Inbox pane — implementation plan

Status: proposed; no application code is changed by this document.

## Goal and navigation

Add a **Threads** view at the same level as **Inbox** within the existing Inbox
pane. The Inbox destination in the app shell remains the entry point.

```text
Inbox destination
├── Inbox                    top-level view
│   ├── New                  Inbox-only subtab
│   └── Postponed            Inbox-only subtab
└── Threads                  top-level view
    └── All followed threads, unread and read
```

The pane header switches between Inbox and Threads, as in the supplied design
reference. New and Postponed are visible only under Inbox. The header refresh
control refreshes the selected view. Switching views preserves their independent
scroll positions, selected Inbox subtab, loaded data, and in-progress operations
for as long as the Inbox destination remains open. Leaving the Inbox
destination releases the paginated Threads list and any open thread snapshot.

The Threads view is scoped to the currently selected team, matching Mattermost's
Threads view. A team switch clears selection and starts that team's list at its
first page. If no team is selected, show a useful empty state rather than
requesting threads with an invalid team ID. The existing shell Inbox indicator
continues to reflect the New queue; opening Threads does not redefine it.

## List content and interaction

Show **all followed threads**, including those with no unread replies, ordered
by most recent thread activity first. Do not use Inbox's unread-only snapshot as
the list source. Each row has a stable root-post ID and shows the channel or
dialog context, root author/avatar, root message preview, last activity, and
unread reply count when greater than zero. Follow the attached reference for
the compact row layout. Use shared message rendering where content is rendered
as Markdown; treat server content and links as untrusted. Do not fetch the full
conversation for every list row.

Rows have **no Done or Postpone controls**. A row is one navigation target with
keyboard, focus, touch, and screen-reader behavior. The row's accessible label
includes the unread reply count. Read rows remain in the list without an unread
badge. The requested count is the unread message count **on each thread row**;
there is no new top-level Threads badge in this design.

Opening a row uses the existing `ThreadPane` and responsive navigation: beside
the list when space permits, or as a route on narrow widths. Preserve the list's
scroll position and selected row when the conversation opens or closes. When
unread replies exist, position at the first unread boundary; otherwise position
at the end.

## Mattermost API and pagination

Use the documented Mattermost API v4 endpoint:

```http
GET /api/v4/users/{user_id}/teams/{team_id}/threads?extended=true&page=0&per_page=60
```

This endpoint lists followed threads and supports `page` and `per_page`. Its
response provides the root post, reply and unread counters, participants, and
the total number of threads. The existing repository already maps these into
`FollowedThread`; retain explicit DTO-to-domain mapping and batch any missing
root authors. Use the returned root post for the preview and fetch full posts
only when a thread opens.

Load 60 rows initially and request further pages as the user approaches the
end, with a single in-flight page request. Merge by root-post ID and stop when
the loaded unique count reaches the reported total or the server returns an
empty page. If a page repeats without adding a new item, stop and show a
recoverable pagination error instead of looping. Refresh restarts from page zero
and keeps useful rows visible until the new first page succeeds. Because an
active thread list can change between page requests, deduplicate and use an
authoritative refresh to restore ordering after realtime updates.

The current client uses an undocumented `before` cursor for followed-thread
pagination. The published API contract specifies `page` and `per_page`; align
the new view with those parameters, and verify the existing list and Inbox
consumers when adapting the shared API method. Keep `since`, `deleted`, and
`totalsOnly` outside the initial list flow. Do not use an unread-only filter:
history must remain visible.

API source: [Mattermost API v4 thread operations](https://github.com/mattermost/mattermost/blob/master/api/v4/source/users.yaml).
Product behavior: [Mattermost threaded discussions](https://docs.mattermost.com/messaging/organizing-conversations).

## Read state and Inbox coordination

Opening from **Threads** marks the thread viewed only after the complete thread
has loaded and rendered. Use the timestamp captured before loading began for
`PUT /api/v4/users/{user_id}/teams/{team_id}/threads/{thread_id}/read/{timestamp}`
so replies arriving during loading remain unread. Do not mark read on a tap
that fails to open or on a partial thread load.

After a successful read, update the row's count and reconcile the New Inbox
thread item and counts from the same authoritative state. A failed read keeps
the count and content visible, reports the failure in the open thread, and
allows retry. Later replies can make a read thread unread again. A read in New
Inbox, an unfollow action, or a server event must also reconcile the Threads
list when it is open.

Keep the existing **New Inbox** behavior: opening an Inbox card does not mark
it read; Done is its explicit action. This is an entry-point policy, not a
different thread-loading implementation. The shared thread pane should receive
that policy from navigation. The Postponed queue remains unchanged.

## State, architecture, and realtime

- Give the Threads view its own route-owned Riverpod list state: items, selected
  team, page/total, initial load, refresh, and pagination statuses. Keep it
  separate from the session-owned New/Postponed snapshot. No thread bodies,
  list pages, cursors, or sync metadata are persisted in Drift.
- Reuse the existing domain `ThreadRepository`, `FollowedThread` mapping, and
  shared thread pane. All REST remains behind `MattermostApi`; realtime events
  flow through the existing session `WebSocketGateway`. UI/controllers do not
  access HTTP or storage directly.
- Reconcile `thread_updated`, `thread_follow_changed`, and
  `thread_read_changed` with the open list. Prefer an authoritative refresh
  when the event lacks a complete projection. Handle reconnect and WebSocket
  sequence gaps by refreshing while retaining visible data. Ignore duplicate
  events by root ID and remove unfollowed or deleted threads.
- Cancel superseded requests and subscriptions on team change or disposal.
  Bound concurrent requests and author batches; honor server rate limits and
  retry with backoff and jitter where automatic retry is appropriate.

## Loading and failure states

| Situation | Expected behavior |
| --- | --- |
| First load | List-level progress, followed by rows or a clear empty state |
| First-load failure | Explicit retry in the Threads view |
| Refresh | Keep existing rows and scroll position; show unobtrusive progress |
| Refresh failure | Keep rows and offer retry |
| Next page | Keep rows and show an inline loading affordance |
| Next-page failure | Keep rows and show an inline retry |
| Read failure | Keep unread count and open content; expose retry |
| Team switch | Cancel old-team work and load the new team's first page |

## Implementation sequence

1. Extend the Inbox pane header with the two top-level views. Keep New and
   Postponed inside Inbox; give each top-level view separate navigation and
   refresh state.
2. Adapt the shared followed-thread API/repository pagination to the documented
   request shape, then build the Threads list state using that repository.
3. Add the list rows and empty, loading, refresh, and pagination states. Connect
   row selection to the shared thread navigation at compact and wide widths.
4. Apply mark-on-open for Threads navigation, synchronize successful reads and
   unfollows with the New Inbox snapshot, and preserve Inbox's existing explicit
   Done behavior.
5. Connect thread realtime and recovery events; update feature and architecture
   notes after implementation.

## Verification and acceptance

- The header shows Inbox and Threads as peers. New and Postponed appear only
  under Inbox. Switching views retains the relevant tab and list positions.
- Recent and historical followed threads appear in activity order. Additional
  pages load older threads without duplicate rows; empty, changing, and failed
  pages terminate safely.
- A row's badge matches its server `unread_replies` value. Opening a complete
  thread marks only the loaded boundary viewed, clears the corresponding New
  Inbox item after success, and preserves replies that arrive during loading.
- Threads rows never show Done or Postpone. Opening a New Inbox card still leaves
  it unread until Done.
- Initial failure, refresh with data, pagination failure, read failure, team
  switching, unfollow, deletion, reconnect, and sequence-gap recovery retain
  useful content and converge to server state.
- Widget tests cover compact and expanded widths, both sides of relevant
  breakpoints, large text scale, keyboard/focus navigation, semantic counts,
  and light/dark themes. Run focused tests, then the full suite because shared
  navigation/API/realtime behavior changes. Format changed Dart files and run
  `flutter analyze` when implementation begins.
