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

Message text is still rendered as plain text. Markdown, files, threads,
WebSocket reconciliation, deletion tombstones, and mutation outbox behavior are
separate capabilities.
