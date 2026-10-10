# Posts and permalinks

Channel history is a volatile, network-first projection of Mattermost posts.
Replies are collected for thread summaries but displayed in the thread feature,
not duplicated as channel roots.

## Channel pagination

The newest page uses `page=0&per_page=60`. Older pages use
`before=<raw_post_id>`. The cursor comes from the last ID in the raw
`PostList.order`, before replies are filtered out. A page that contains only
replies therefore still advances pagination.

Before root filtering, the mapper groups replies by `root_id` and records their
IDs and latest `create_at`. The displayed reply count is the larger of the
server's `reply_count` and the number of unique replies seen by the client. This
keeps the thread affordance when a server summary is stale or when a root and
its replies arrive on different pages.

The controller merges pages by post ID and sorts by `create_at`, then ID.
Closing the channel releases the snapshot. An initial failure shows retry;
pagination failures keep the history already displayed.

## Sending and realtime changes

After a successful send, the returned post is inserted into the active channel
or thread snapshot. Realtime `posted`, `post_edited`, and `post_deleted` events
use the same merge and replacement rules as REST results. Duplicate REST and
WebSocket delivery does not create duplicate posts. Subscriptions are scoped to
the open channel or thread and are cancelled with that route's auto-disposed
state.

Realtime events received while an initial load, refresh, focus request, or page
request is in flight are replayed over its response before publication. Post
`update_at` revisions prevent a delayed event from replacing a newer REST
projection. A WebSocket reconnect or sequence gap starts one coalesced,
authoritative reload while preserving the useful snapshot already on screen;
events received during that recovery are replayed over the replacement too.

## Permalink navigation

Links for the active server with the form `/<team-name>/pl/<post-id>` stay
inside the app. Links to another origin and other HTTP(S) links keep their
external behavior. The resolver requests `GET /posts/{post_id}` and
`GET /channels/{channel_id}` to identify the channel, root post, reply, and
thread destination.

Historical navigation creates a separate `/post/:postId` route. It loads a
bounded window around the root with parallel `before`, `after`, and root-post
requests. The window keeps independent older and newer cursors, and proximity
to either edge loads that direction.

The source route stays mounted under the permalink route. Its snapshot, scroll
position, focus, and composer draft remain intact, even when the target belongs
to the same channel. Popping the permalink releases only its route-scoped state.

Wide layouts show the target channel and, when needed, a side thread. Compact
layouts open a thread target directly in `ThreadPane`; Back, Escape, Close, and
the platform back gestures return to the exact source screen.

## Relevant code

- `lib/src/ui/posts/`
- `lib/src/data/repositories/mattermost_post_repository.dart`
- `lib/src/data/mappers/mattermost_message_mapper.dart`
- `lib/src/domain/repositories/post_repository.dart`
