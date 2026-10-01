# Inbox and Postponed

Inbox is a network-first attention queue built on top of Mattermost data. It is
separate from the official Mattermost clients and combines unread followed
threads, mentions, eligible channel messages, direct messages, and integration
messages in one destination.

The UI has two queues. `New` is reconstructed from Mattermost REST data and
updated from the active session's realtime stream. `Postponed` stores only
content-free references in Mattermost user preferences. Message text is never
written to preferences or Drift.

## Presentation and ordering

`New` is one flat list. It has no Mentions, Group mentions, Bots and
integrations, Direct Messages, or Threads sections. Items from every source are
interleaved by `lastActivityAt`, newest first; the stable item key breaks equal-time
ties. `Postponed` also remains newest-activity first, with `postponedAt` as its
first tie-breaker.

The latest event is source-specific:

| Item | Latest event | Unread counter |
| --- | --- | --- |
| Followed thread | Date of the last post in the thread | Unread messages in the thread from the CRT projection |
| Direct-message bundle | Date of the latest unread message from that sender in that dialog | Messages in the bundle |
| Channel root | Date of that root post | No aggregate badge; the card represents one message |

Each New item follows the message-search result layout, with more detail:

1. The header is only the channel display name, or `Direct message` for direct
   and group-message dialogs. It does not include `Thread` or a mention reason.
2. The author and message timestamp remain visible as message metadata.
3. A card renders the complete selected post body with the shared
   `MessageContent` read path. It must not fall back to
   plain text, truncate to a fixed number of lines, or implement a smaller
   Inbox-only Markdown dialect.
4. A divided Updates block appears between the message and actions. Important
   values such as counts, times, `You`, and user-group handles use compact
   theme-aware tag backgrounds, align with the message content column, and wrap
   at narrow widths or large text scales.
5. Read and Postpone controls sit in a divided footer inside the same bordered,
   zero-elevation surface as the message. Opening the message area navigates to
   the shared thread, channel, or permalink destination without implicitly
   performing either action.

The rendered post is the root for a thread, the latest unread message for a
direct-message bundle, and the item post for a channel root. Server-provided
Markdown and navigation targets keep the shared renderer's security rules.
Action failures keep useful content visible and expose local failure feedback
instead of replacing the queue.

The Updates block is derived from these presentation fields:

| Source | Updates |
| --- | --- |
| Followed thread | `<count> new replies, last one at <time>`; when present, `You`, each matching `@<group slug>`, `@channel`, or an unclassified `Mention`, followed by `mentioned` |
| Direct or group-message dialog | `<count> new messages, last one at <time>` when the bundle contains more than one message; no Updates block for a single message |
| Current referenceable user-group mention | `@<group slug> mentioned` |
| Direct or keyword mention of the current user | `You mentioned` |
| Channel-wide mention | `@channel mentioned` |
| All-messages subscription | `New post in a channel` |

For channel roots, a current-user mention takes precedence over a matching
referenceable user-group mention. Classification retains the matching
user-group slug through the domain model instead of trying to recover it from
rendered Markdown.

The information needed to build Updates has explicit owners. CRT supplies a
thread's unread-reply count, unread-mention count, last-viewed boundary, and
last-reply timestamp. For threads with unread mentions, the repository pages
thread posts newer than that boundary and applies the normal mention classifier
to recover personal, user-group, and channel-wide reasons. The dialog bundle
owns its message count and latest message timestamp. A channel-root candidate
owns its classified attention reason and matching group handle.

## Sources and snapshot construction

| Source | Snapshot | Read action |
| --- | --- | --- |
| Followed thread | Unread CRT threads for each team | Update thread read timestamp |
| Channel root | Channel/member counters, then unread posts | Selective viewed-post preference, or view the channel when it is the only remaining root |
| Direct or group-message root | Dialog counters, then unread posts | View the dialog channel |
| Postponed item | `postponed_messages` preferences, then posts by ID | No implicit completion |

The repository loads all teams, their channels and memberships, unread followed
threads, postponed preferences, viewed-post preferences, candidate unread
ranges, referenceable user groups, and required authors. It assembles a
complete `InboxSnapshot` before replacing the UI state. Initial failure shows
retry. Refresh failure keeps the old snapshot.

Unread channel requests run in bounded groups of four. Followed threads page by
`before=<root_post_id>` until a page has fewer than 60 items or a cursor repeats.
For followed threads whose CRT projection reports unread mentions, thread posts
newer than `last_viewed_at` are paged in bounded groups of four. Post and author
hydration uses bounded ID batches.

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
`silent_notification=true` do not enter `New`. Bot and automation
classification checks `User.is_bot` plus `from_bot`, `from_webhook`, and
`from_plugin` props. Automation status no longer creates a presentation
section; it remains metadata used to avoid combining incompatible dialog
messages.

## Item model and canonicalization

`ThreadInboxItem` uses `thread:<rootPostId>` as its key and represents one
unread followed thread. `ChannelPostInboxItem` uses `post:<postId>` and contains
exactly one non-dialog root. Multiple eligible roots from the same channel are
always separate items. `DirectMessageBundleInboxItem` uses the dialog channel,
author, automation class, and first post to identify unread messages from the
same sender.

Canonicalization runs before presentation:

1. An eligible followed thread claims its root and replies.
2. Remaining direct and group-message roots become dialog candidates and are
   bundled by channel, sender, and automation class.
3. Every remaining non-dialog root becomes its own channel item; roots from one
   channel are never collapsed into a channel bundle.
4. Duplicate post IDs keep the strongest reason: direct, keyword, group,
   channel, then all-messages subscription.
5. Postponed references suppress matching New posts or thread roots.
6. Viewed-post references suppress only matching non-dialog channel roots from
   New. They neither suppress threads or dialogs nor create Postponed items.

REST pages and realtime delivery are idempotent by post ID. One thread root may
appear in at most one item. `New` and `Postponed` cannot contain the same post ID
or thread root. A new explicit mention can reactivate a postponed thread and
remove it from the postponed projection.

The item-local counter is the value shown on the card: unread replies for a
thread and bundled unread messages for a dialog. A direct-message bundle
contributes each bundled message to the New tab count, while a thread remains
one communication in that tab count. Only `New` controls the Inbox indicator in
app navigation.

## Read behavior for channel roots

Mattermost has no operation that marks one arbitrary channel post read while
preserving other unread posts. Inbox therefore uses a separate user preference
projection for non-dialog channel roots.

Read evaluates the reconciled New snapshot for the selected root's channel:

- When two or more eligible channel-root items remain, merge the selected post
  ID into that channel's viewed-post preference. Do not call the channel-viewed
  endpoint. Remove only the selected item after the preference write succeeds.
- When the selected item is the only remaining eligible channel root, view the
  whole channel with the normal Mattermost endpoint and delete that channel's
  viewed-post preference. The channel view clears the server unread state; the
  preference deletion prevents stale selective-read IDs from accumulating.
- Dialog bundles do not participate in the ordinary channel-root count. Thread
  Read updates the thread read timestamp and also marks its root read: it stores
  the root ID in the viewed-post preference when other eligible channel roots
  must be preserved, or views the channel when none remain. Dialog Read views
  the dialog channel and removes all New dialog items covered by that
  server-side view.

The count is taken after eligibility, canonicalization, postponed suppression,
and viewed-post suppression. Preference writes happen before optimistic removal
for the multiple-root case. For the single-root case the irreversible channel
view happens before preference cleanup. If the channel view fails, the item
stays in New. If only preference cleanup fails, the read still completes and
the repository retries that deletion before its next authoritative load. A
later process also removes viewed-post preferences whose channel read boundary
has already caught up, so cleanup survives an app restart.

### Viewed-post storage

Viewed-post state is account-owned remote metadata, separate from Postponed. It
uses one preference per channel:

```json
{
  "user_id": "<current-user-id>",
  "category": "inbox_viewed_posts",
  "name": "<channel-id>",
  "value": "{\"v\":1,\"channel_id\":\"<channel-id>\",\"post_ids\":[\"<post-id>\"]}"
}
```

The preference contains IDs only, never message content. Reads
deduplicate IDs, ignore malformed or mismatched records, and filter only the
matching channel. A merge re-reads the current preference immediately before a
serialized local read-modify-write so concurrent actions in this client do not
lose IDs. Each mutation writes or deletes one channel preference.

Mattermost limits a preference value to 20,000 Unicode code points. The encoded
value must be measured before writing. The client must not silently discard old
IDs because doing so can resurrect messages in Inbox. If the list cannot fit,
the selective Read fails visibly and leaves the item in New until a deliberate
channel-wide view or another product-approved compaction policy is chosen.

## Postponed storage

Postponed uses a different category and a per-item preference, not the
per-channel viewed-post list:

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
user completes it with Remove or Done. For a direct-message bundle, Postpone
stores the latest displayed message only; its other unread messages remain in
New and can therefore coexist with that postponed reference after refresh.

## Realtime and recovery

The authenticated session owns one WebSocket connection. Inbox subscribes to a
bounded set of post, thread, channel, preference, membership, user, and
referenceable-user-group events for channels in its last REST snapshot. Root
post changes update the volatile snapshot by post ID. Malformed or unsupported
individual events are ignored without declaring the healthy stream invalid.

The loaded viewed-post projection also filters root-post realtime events, so an
edit or duplicate delivery cannot reinsert a locally viewed item. Read and
Postpone mutations serialize against queued realtime changes so their item
counts and single-root/multiple-root decisions cannot be overwritten by an
older local snapshot. Preference changes from another client are reconciled by
the next authoritative REST refresh.

Thread update, follow, and read events request an authoritative refresh because
their WebSocket payloads do not contain the full thread projection needed for
last-event ordering and unread counters.

Reconnect, an observed sequence gap, or app resume requests an authoritative
REST refresh. The current snapshot stays visible while recovery runs. A newly
accepted foreground post can produce an in-app notification; initial load,
recovery, edits, deletes, and duplicate delivery do not.

The header shows green for connected, amber for connecting, and red for
disconnected. System push notifications remain outside this feature.

## Known limits

The standard API exposes historical channel-root mention counters but not the
post IDs and reasons behind those counters. The client compares reconstructed
mentions with `mention_count_root` and marks the snapshot incomplete when it
finds fewer. Thread replies can be hydrated after the CRT read boundary, but
presence-dependent historical `@here` still cannot be classified exactly and
is shown as an unclassified `Mention`. Exact reconstruction would require a
server extension that returns unread attention post IDs and their reasons.

Mattermost preferences do not provide compare-and-swap semantics. Re-reading
and serializing mutations prevents lost updates inside one client instance, but
two devices can still race while adding viewed post IDs to the same channel
preference. A server-side selective-read primitive or one preference per post
would be needed to eliminate that cross-device race.

The single-root decision is based on a snapshot. A new channel post accepted by
the server between that decision and the channel-view request can also be marked
read by Mattermost. The controller must reconcile queued realtime events with
an authoritative refresh, but the API cannot make this sequence atomic.

An unavailable postponed post currently remains stored on the server but has
no placeholder in the UI. Postponing a followed thread stores the preference,
but the follow-up mark-read and unfollow sequence is still pending.
Incremental realtime handling is strongest for root post changes; REST refresh
remains the authoritative source for followed-thread and preference
reconciliation.

## Relevant code

- `lib/src/features/inbox/`
- `lib/src/data/realtime/session_realtime_service.dart`
- `lib/src/data/realtime/mattermost_websocket_gateway.dart`
