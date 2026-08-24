# Channel posts

The posts slice is network-first. Creating a channel controller always loads
`page=0&per_page=60`; no post, reaction, order, or pagination state is read from
or written to Drift. The auto-disposed controller owns the currently visible
pages and releases them when the channel closes.

Older history uses `before=<post_id>`. The cursor is the last id from the raw
`PostList.order`, including replies, while the visible list contains only posts
with an empty `root_id`. This lets reply-only pages advance pagination without
showing replies as channel roots. Pages are merged by post id and displayed in
stable `create_at`, then id, order.

The server's root `reply_count` and `last_reply_at` summaries drive the thread
affordance. Opening a thread performs a separate authoritative thread request.
An initial network failure shows a retry state; an older-page failure preserves
the history already held in memory.

See the official [post endpoint specification](https://github.com/mattermost/mattermost/blob/master/api/v4/source/posts.yaml).
