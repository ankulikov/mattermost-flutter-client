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

The server's root `reply_count` and `last_reply_at` summaries normally drive the
thread affordance. Some channel responses contain replies while their root still
has a stale zero summary, so the controller also keeps observed reply ids grouped
by `root_id`. Across loaded pages it uses the greater of the server count and the
deduplicated observed count, and the latest observed reply time. This volatile
summary also works when a reply arrives on an earlier page than its root.

Opening a thread performs a separate authoritative thread request. An initial
network failure shows a retry state; an older-page failure preserves the history
already held in memory.

See the official [post endpoint specification](https://github.com/mattermost/mattermost/blob/master/api/v4/source/posts.yaml).
