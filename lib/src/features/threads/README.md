# Message threads

Threads are an offline-first projection over normalized posts. The root and
each reply remain regular cached post rows; `thread_post_orders` records thread
membership/order and `thread_sync_states` records whether the bounded refresh
reached the end. This avoids copying message bodies into a second table and
allows a reply to be persisted before its root exists locally.

## API strategy

Mattermost API v4 does not document a way to request only root posts from
`GET /api/v4/channels/{channel_id}/posts`. Channel pages therefore persist all
posts and filter roots locally using `root_id`.

Opening a thread uses the dedicated
`GET /api/v4/posts/{post_id}/thread` endpoint. Its `perPage`, `fromPost`, and
`fromCreateAt` parameters are used to fetch consecutive pages. Refreshes use 60
posts per request and stop after 20 pages so an unexpectedly large thread
cannot create unbounded work. `has_next` remains reflected as an incomplete
local sync state if that safety limit is reached.

See the official
[post endpoint specification](https://github.com/mattermost/mattermost/blob/master/api/v4/source/posts.yaml).

## Orphan replies and consistency

When a reply arrives before its root, the reply is saved immediately with its
real root id and indexed in `thread_post_orders`. No placeholder root is
created: placeholders tend to leak incorrect author, timestamps, deletion, and
permission state into UI. The channel list excludes the orphan. A thread refresh
retrieves the authoritative root and replies together and publishes them only
through the database-backed stream.

Root `reply_count` and `last_reply_at` are server summaries and may be newer
than the locally cached reply set. The channel uses those summaries for its
reply affordance; the open panel displays the replies actually available in its
thread projection. WebSocket updates and gap reconciliation must upsert both the
post and its thread membership transactionally. Deletes must retain a tombstone
until reconciliation so counts and completeness can be repaired instead of
silently drifting.
