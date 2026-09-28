# Inbox and Postponed

Inbox is a network-first attention queue built on top of Mattermost data. It is
separate from the official Mattermost clients and combines unread followed
threads, mentions, eligible channel messages, direct messages, and integration
messages in one destination.

The UI has two queues. `New` is reconstructed from Mattermost REST data and
updated from the active session's realtime stream. `Postponed` stores only
content-free references in Mattermost user preferences. Message text is never
written to preferences or Drift.

## Sources

| Source | Snapshot | Read action |
| --- | --- | --- |
| Followed thread | Unread CRT threads for each team | Update thread read timestamp |
| Channel post | Channel/member counters, then unread posts | View the channel |
| Direct or group message | Dialog counters, then unread posts | View the channel |
| Postponed item | `postponed_messages` preferences, then posts by ID | No implicit completion |

The repository loads all teams, their channels and memberships, unread followed
threads, postponed preferences, candidate unread ranges, and required authors.
It assembles a complete `InboxSnapshot` before replacing the UI state. Initial
failure shows retry. Refresh failure keeps the old snapshot.

Unread channel requests run in bounded groups of four. Followed threads page by
`before=<root_post_id>` until a page has fewer than 60 items or a cursor repeats.
Post and author hydration uses bounded ID batches.

## Eligibility

Direct and group-message roots are Inbox candidates when they are unread.
Ordinary channel roots need either a reconstructed mention reason or an
all-messages subscription. The subscription resolves to true when:

```text
member.mark_unread == all
AND (
  effective(member.desktop, user.desktop) == all
  OR effective(member.push, user.push) == all
)
```

A channel value of `default` inherits the user's setting. Email settings do not
participate because they describe a delivery transport, not the Inbox queue.

The historical classifier recognizes `@username`, an enabled first name,
custom mention keys, current referenceable user groups, `@channel`, and `@all`.
It intentionally omits `@here`: a REST snapshot does not contain the user's
send-time presence. Realtime `posted` events use the server's `mentions` list
when it is available.

System posts, deleted posts, the current user's own posts, and posts with
`silent_notification=true` do not enter `New`. Bot and automation classification
checks `User.is_bot` plus `from_bot`, `from_webhook`, and `from_plugin` props.

## Item model

`ThreadInboxItem` uses `thread:<rootPostId>` as its key and represents one
unread followed thread. `ChannelPostInboxItem` uses `post:<postId>` and contains
one root post. `DirectMessageBundleInboxItem` uses the channel, author, and first
post to identify a presentation bundle.

Direct messages group by channel, author, and automation class within the
current snapshot. Human messages and automation messages never share a bundle.
The UI postpones only the latest message from a direct-message bundle. The
remaining unread messages stay in `New`; a later refresh may therefore show the
same conversation in both tabs with different post IDs.

Items appear in one of five sections:

- Mentions
- Group mentions
- Bots and integrations
- Direct Messages
- Threads

An unread mention inside a followed thread appears under Threads. Otherwise a
thread root keeps its source when possible: a direct root stays with direct
messages, and a mentioned channel root stays with mentions.

## Canonicalization and queue rules

Canonicalization runs before presentation grouping:

1. An eligible followed thread claims its root and replies.
2. Remaining direct and group-message roots become direct candidates.
3. Remaining roots become channel candidates.
4. Duplicate post IDs keep the strongest reason: direct, keyword, group,
   channel, then all-messages subscription.
5. Postponed references suppress matching New posts or thread roots.

REST pages and realtime delivery are idempotent by post ID. One thread root may
appear in at most one item. `New` and `Postponed` cannot contain the same post ID
or thread root. A new explicit mention can reactivate a postponed thread and
remove it from the postponed projection.

Both queues sort by latest activity, newest first. `postponedAt` breaks ties in
the postponed queue. A direct bundle contributes its number of messages to the
tab count; a thread counts as one communication. Only `New` controls the Inbox
indicator in app navigation.

## Postponed storage

Each postponed post or thread has one Mattermost preference:

```json
{
  "user_id": "<current-user-id>",
  "category": "postponed_messages",
  "name": "<canonical-post-id>",
  "value": "{\"v\":1,\"post_id\":\"<canonical-post-id>\",\"added_at\":1788432000000,\"kind\":\"post|thread\"}"
}
```

Thread references use the root ID. `target_post_id` may retain the selected
reply while the root remains canonical. Preference writes and deletes use
batches of at most 100.

This per-item format avoids the 20,000-character preference value limit and the
read-modify-write race of one JSON array. Loading deduplicates by canonical ID
and keeps the newest valid timestamp. Malformed preferences are ignored.

Postpone writes the preference before moving an item in the UI. A failed write
leaves the item in `New`. Remove deletes the exact preference; a failed delete
keeps the item in `Postponed`. Opening a postponed item does not remove it. The
user completes it with Remove or Done.

Viewing a channel or direct message marks that Mattermost channel as viewed, so
all older New items from the same channel leave the queue after a successful
read action. Mattermost has no operation that marks one arbitrary channel post
read while preserving older unread posts.

## Realtime and recovery

The authenticated session owns one WebSocket connection. Inbox subscribes to a
bounded set of post, thread, channel, preference, membership, and user events
for channels in its last REST snapshot. Root post changes update the volatile
snapshot by post ID. Malformed or unsupported individual events are ignored
without declaring the healthy stream invalid.

Reconnect, an observed sequence gap, or app resume requests an authoritative
REST refresh. The current snapshot stays visible while recovery runs. A newly
accepted foreground post can produce an in-app notification; initial load,
recovery, edits, deletes, and duplicate delivery do not.

The header shows green for connected, amber for connecting, and red for
disconnected. System push notifications remain outside this feature.

## Known limits

The standard API exposes historical mention counters but not the post IDs and
reasons behind those counters. The client compares reconstructed mentions with
`mention_count_root` and marks the snapshot incomplete when it finds fewer.
Exact reconstruction, including historical `@here`, would require a server
extension that returns unread attention post IDs and their reasons.

An unavailable postponed post currently remains stored on the server but has no
placeholder in the UI. Postponing a followed thread stores the preference, but
the follow-up mark-read and unfollow sequence is still pending. Incremental
realtime handling is strongest for root post changes; REST refresh remains the
authoritative source for followed-thread and preference reconciliation.

## Relevant code

- `lib/src/features/inbox/`
- `lib/src/data/realtime/session_realtime_service.dart`
- `lib/src/data/realtime/mattermost_websocket_gateway.dart`
