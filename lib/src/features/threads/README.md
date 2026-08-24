# Message threads

Threads are network-first, volatile domain snapshots. Opening a thread calls
`GET /api/v4/posts/{post_id}/thread`; closing its auto-disposed controller drops
the root, replies, and completeness flag from memory. Drift is not involved.

The repository follows `fromPost` and `fromCreateAt` for at most 20 pages per
load. It maps the complete response once, publishes root and replies together,
and sorts replies by `create_at ASC`, then post id. If the safety bound is hit,
`isComplete` remains false.

See the official [post endpoint specification](https://github.com/mattermost/mattermost/blob/master/api/v4/source/posts.yaml).
