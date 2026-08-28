# Message threads

## Followed threads (CRT)

The Threads sidebar destination loads followed threads with
`GET /api/v4/users/{user_id}/teams/{team_id}/threads`. It requests the maximum
60-item page with `extended=true`; the response already contains each root
post, reply summary, participants, and server-authoritative `unread_replies` and
`unread_mentions`. Root-author profiles that are not among the returned
participants are resolved in one optional `POST /users/ids` batch. The list
never loads every root through `GET /posts/{id}/thread`.

Older list pages use the root id of the last displayed thread as the `before`
cursor. Pages are deduplicated by root id and remain visible if refresh or
pagination fails. An unread thread shows the server-authoritative
`unread_replies` count. Opening an item is the point where the existing
authoritative thread endpoint is called.

Threads are network-first, volatile domain snapshots. Opening a thread calls
`GET /api/v4/posts/{post_id}/thread`; closing its auto-disposed controller drops
the root, replies, and completeness flag from memory. Drift is not involved.

The repository requests `direction=up` and follows the server's `next_post_id`
with `fromPost` plus `fromCreateAt` until `has_next=false`. Repeated or invalid
cursors fail the load instead of exposing a partial conversation. It maps the
complete response once, publishes root and replies together, and sorts replies
by `create_at ASC`, then post id.

When a followed thread is opened, its `unread_replies` snapshot places an
`unread messages` divider before the last unread replies. The pane scrolls that
divider into view after the complete thread's first frame. Only then it calls
`PUT /users/{user_id}/teams/{team_id}/threads/{thread_id}/read/{timestamp}`;
`timestamp` is captured immediately before the first thread-page request, so a
reply arriving during pagination is not accidentally marked as read. A
successful update clears the volatile unread counters in the followed list.
Threads without unread replies open at the end of the conversation.

Deleted replies returned by the server retain their place in the conversation
and are rendered as placeholders without message contents or reactions.

Replies use the same text-only composer as channel posts. Creation goes through
`POST /api/v4/posts` with the channel id, root post id, message, and a client
`pending_post_id`. A successful response is merged into the open thread and its
root summary immediately, while a failure keeps the draft available for retry.
No WebSocket transport is involved in sending.

Root and reply bodies use the same `MattermostMarkdown` widget as channel posts,
so formatting and URL safety do not diverge between the channel and thread
surfaces. See [`docs/MARKDOWN.md`](../../../../docs/MARKDOWN.md).

Root and reply reactions use the same optimistic toggle and custom emoji cache
as channel posts. Failed reaction requests roll back only the affected reaction
while preserving the loaded thread.

See the official [post endpoint specification](https://github.com/mattermost/mattermost/blob/master/api/v4/source/posts.yaml).
