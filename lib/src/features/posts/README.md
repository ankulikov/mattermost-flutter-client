# Channel posts

The posts slice owns channel history, paging, and the presentation state that
keeps a reopened channel stable while its latest page is reconciled.

## API strategy

Mattermost's `GET /api/v4/channels/{channel_id}/posts` endpoint defaults to 60
posts per page; the global API limit is 200. This client deliberately uses 60 to
keep response parsing, profile lookup, and Drift transactions bounded. The most
recent page uses `page=0&per_page=60`. Older history uses
`before=<oldest_post_id>&page=0&per_page=60`, avoiding page-number drift when
messages arrive while the user is reading.

The endpoint also accepts `since=<unix_ms>`, which can detect posts modified
after a stored timestamp. The server returns all matching posts up to 1000, but
the API explicitly does not guarantee that they are consecutive. It is useful
for future WebSocket-gap reconciliation, not as the only source for the
contiguous recent page. See the official
[post endpoint specification](https://github.com/mattermost/mattermost/blob/master/api/v4/source/posts.yaml)
and [pagination conventions](https://github.com/mattermost/mattermost/blob/master/api/v4/source/introduction.yaml).

## Offline-first behavior

`ApiChannelPostRepository` maps wire DTOs to cache models and writes authors,
posts, reactions, ordering, and per-channel sync metadata atomically. Every row
is scoped by account/server ID. `ChannelPostStore` then maps database rows to
domain entities; the controller never exposes the HTTP response directly.

On open, cached messages are rendered immediately and the latest page refreshes
in the background. If that refresh adds messages, they remain outside the
visible window until the user chooses **Show recent messages**, preventing a
scroll jump. Reaching the visual top requests the next `before` page. A reversed
list keeps the current viewport anchored when older rows are prepended.

Because a raw server page can contain only replies, the visible root list may
still have no scroll extent after a successful page load. After every layout and
completed `loadOlder`, the list checks its scroll metrics and automatically
loads another raw page while `hasOlder` remains true. Automatic filling is
limited to 20 consecutive pages; if the viewport is still not filled, an
explicit **Load older messages** button remains available. A paging failure
stops automatic loading instead of creating a retry loop.

Message text is still rendered as plain text. Markdown, files, WebSocket
reconciliation, deletion tombstones, and mutation outbox behavior are separate
capabilities.

## Channel history and replies

The documented channel-history endpoint does not expose a root-only filter.
Every returned post is normalized, but only posts whose `root_id` is explicitly
empty are added to `channel_post_orders`. Replies are associated with their
thread by `cached_channel_posts.root_id`, so replies from different threads can
arrive in the same page without appearing as standalone channel messages. A
newly received reply also does not trigger the channel's **Show recent
messages** affordance.

`cached_channel_posts.root_id` is nullable only for migration safety. `null`
means that an old cache row predates thread-aware storage; it is not treated as
a root. New network rows always store either `''` for a root or a non-empty root
post id for a reply. This prevents a legacy reply from being misclassified.

The raw channel page cursor remains independent from the filtered root order.
That distinction matters because using the oldest visible root as the next
`before` cursor can skip replies or repeat server pages.

`channel_history_entries` records every raw post id from `PostList.order`, not
only visible roots. A page-0 refresh retains the previously loaded deep cursor
only when the new page overlaps that active raw segment. If more than one page
arrived while the channel was closed and there is no overlap, the active
presentation segment is restarted atomically and older loading continues from
the last raw `post_id` in the new page. This prevents a jump from page 0
directly to the old cached cursor. Older paging is not allowed to race the
latest-page refresh.
