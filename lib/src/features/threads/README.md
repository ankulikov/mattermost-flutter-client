# Message threads

Threads are network-first, volatile domain snapshots. Opening a thread calls
`GET /api/v4/posts/{post_id}/thread`; closing its auto-disposed controller drops
the root, replies, and completeness flag from memory. Drift is not involved.

The repository requests `direction=up` and follows `fromPost` plus
`fromCreateAt` for at most 20 pages per load. It maps the complete response
once, publishes root and replies together, and sorts replies by `create_at ASC`,
then post id. If the safety bound is hit, `isComplete` remains false.

Deleted replies returned by the server retain their place in the conversation
and are rendered as placeholders without message contents or reactions.

Root and reply bodies use the same `MattermostMarkdown` widget as channel posts,
so formatting and URL safety do not diverge between the channel and thread
surfaces. See [`docs/MARKDOWN.md`](../../../../docs/MARKDOWN.md).

See the official [post endpoint specification](https://github.com/mattermost/mattermost/blob/master/api/v4/source/posts.yaml).
