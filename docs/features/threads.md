# Threads

Threads cover the followed-thread list, full thread loading, read state, reply
ordering, and the responsive thread pane shared by channels, permalinks, and
Inbox.

## Followed threads

The list requests
`GET /users/{user_id}/teams/{team_id}/threads?extended=true&per_page=60`.
Further pages use `before=<last_root_post_id>` in the request. Although the
published OpenAPI description lists `page`, the Mattermost server handler reads
`before` and ignores `page`; using `page` caused Inbox's all-page snapshot to
repeat the first page. The response already includes the root,
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

An open thread subscribes to post events by root ID through the session-wide
realtime service, so it can subscribe before the REST load reveals a channel.
Created and edited replies reconcile by post ID, realtime-deleted replies are
removed from the open-thread projection, and reconnect/sequence-gap recovery
reloads the complete thread without temporarily clearing it. Closing the thread
cancels its subscription.

After the first frame of a complete followed thread, the client updates the
thread read timestamp to the time captured before loading began. The timestamp
cannot jump past replies that arrived during the request. Inbox is the
exception: opening an Inbox thread positions the unread boundary but leaves it
unread until the user selects Done on its Inbox card.

## Presentation

The Inbox destination has peer Inbox and Threads views. New and Postponed stay
under Inbox; Threads shows all followed threads for the selected team, including
read threads. The list state belongs to the open destination, while Inbox's
New/Postponed snapshot belongs to the signed-in session. Switching views keeps
their positions and the selected Inbox tab. Successful Threads read operations
refresh the New Inbox projection; opening an Inbox card remains explicitly
completed with Done.

When the content pane is at least `AppBreakpoints.sideThread` wide, `ThreadPane`
opens beside the channel or Inbox content. Narrower layouts route to
`/thread/:rootPostId`. Both paths use the same pane and controller. Closing the
panel or route releases the thread snapshot.

On touch input inside an open thread, tapping a message opens actions while a
long press remains available for native text selection. The context menu starts
with Quote and inserts each selected line into the composer with a `> ` prefix.
The channel's side-thread divider can be dragged or adjusted with the arrow
keys. The thread width stays within 280–700 px while leaving at least 360 px
for channel history. The width is view state and is clamped to the available
space when the window changes size.

## Relevant code

- `lib/src/ui/threads/`
- `lib/src/data/repositories/mattermost_thread_repository.dart`
- `lib/src/domain/repositories/thread_repository.dart`
