# Threads

Threads cover the followed-thread list, full thread loading, read state, reply
ordering, and the responsive thread pane shared by channels, permalinks, and
Inbox.

## Followed threads

The list requests
`GET /users/{user_id}/teams/{team_id}/threads?extended=true` in pages of 60.
Pagination uses `before=<root_post_id>`. The response already includes the root,
reply and unread counters, mention counters, and participants. Root authors not
present in `participants` are fetched in one `/users/ids` batch. The list never
loads every full thread to render its rows.

## Opening a thread

`GET /posts/{post_id}/thread` loads the conversation. The repository requests
upward pages and follows the server's `next_post_id` through `fromPost` and
`fromCreateAt` until `has_next=false`. A repeated or malformed cursor fails the
load instead of presenting an incomplete thread as complete.

Replies sort by `create_at`, then ID. Edits do not change that order. A deleted
reply keeps its position as a placeholder. When unread replies exist, a divider
marks their boundary and becomes the initial scroll target. A followed thread
with no unread replies opens at the end; a thread opened from channel history
starts at its root.

After the first frame of a complete followed thread, the client updates the
thread read timestamp to the time captured before loading began. The timestamp
cannot jump past replies that arrived during the request.

## Presentation

When the content pane is at least `AppBreakpoints.sideThread` wide, `ThreadPane`
opens beside the channel or Inbox content. Narrower layouts route to
`/thread/:rootPostId`. Both paths use the same pane and controller. Closing the
panel or route releases the thread snapshot.

On touch input inside an open thread, tapping a message opens actions while a
long press remains available for native text selection. The context menu starts
with Quote and inserts each selected line into the composer with a `> ` prefix.

## Relevant code

- `lib/src/ui/threads/`
- `lib/src/data/repositories/mattermost_thread_repository.dart`
- `lib/src/domain/repositories/thread_repository.dart`
