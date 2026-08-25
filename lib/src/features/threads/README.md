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
pagination fails. A thread with mentions shows the mention count; otherwise an
unread thread shows a dot. Opening an item is the point where the existing
authoritative thread endpoint is called.

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
