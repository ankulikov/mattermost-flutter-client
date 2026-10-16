# Channels and sidebar

The sidebar is a network-first view of the current team, channel categories,
channels, and direct conversations. Its controller owns the snapshot only while
the authenticated shell is using it.

## Loading and refresh

The initial request loads the user's first team, its channels, channel
memberships, and sidebar categories. Membership read counters are compared with
the channel totals: ordinary channels use the CRT root counters, while direct
and group conversations use the full-message counters. Unread channel names and
icons use the emphasized sidebar treatment; muted channels retain the muted
treatment.

Unread state is updated from `posted`, `channel_viewed`, and `post_unread`
WebSocket events. A reconnect or sequence gap performs an authoritative REST
reload. There is no polling interval: the sidebar loads when its session starts,
updates from realtime events, and reloads on manual refresh or realtime
recovery. Selecting a channel calls the v4 channel-view endpoint and clears the
local highlight after the server accepts the new read boundary.

Direct and group-message names are resolved through the users API. An initial
failure shows a retry state. Manual refresh keeps the existing snapshot visible
until the replacement succeeds and reports a non-blocking failure otherwise.

Sidebar search filters the loaded snapshot locally by the displayed channel or
conversation name. Matches remain in their original categories. Search expands
matching categories temporarily and restores their previous expansion state
when the query is cleared.

## Direct-message avatars

The users batch response supplies a versioned profile reference for each direct
conversation. Visible rows render initials immediately, then request
authenticated avatar bytes through `UserRepository`. Sidebar rows, messages,
and profile cards share the same account-scoped cache and in-flight request.

Mattermost does not expose a separate avatar thumbnail endpoint. The UI limits
decode size for the rendered control. A failed image request leaves the initials
in place and does not block navigation.

## Channel members

The channel header loads its member count from
`GET /channels/{channel_id}/stats`. Activating the count opens a network-first,
read-only member list backed by paged
`GET /channels/{channel_id}/members` requests. Membership responses provide
user IDs and channel roles; each page resolves profile details through the
shared `UserRepository`, so member rows reuse the account-scoped profile and
avatar caches.

At content widths of at least 800 px, the member list opens in a 380 px side
pane. Narrower content opens the same pane as a full-screen route. Closing the
pane releases its member snapshot. Initial failures show an explicit retry;
pagination failures preserve already loaded members.

Member rows use the same compact, avatar-led presentation as direct messages,
omit usernames, and open the shared user profile card when selected.

## Adaptive shell

Compact layouts show Channels and Inbox as separate destinations with bottom
navigation. Medium and expanded layouts keep a navigation rail visible. The
left pane shows either the channel list or the Inbox; an Inbox selection does
not leave an unrelated channel list beside it. Expanded layouts can keep that
left pane visible while a message or thread opens in the working area.

The shell, sidebar, and panes choose their layout from constraints. No feature
branches on mobile versus desktop to select a layout.
On rail layouts, the divider between the channel list and working area can be
dragged or adjusted with the left and right arrow keys. Its width stays within
200–500 px and leaves at least 320 px for the working area. The chosen width
remains in shell view state while destinations change and is clamped when the
window narrows.

## State rules

- Sidebar snapshots, category expansion, pagination state, and sync metadata
  are not stored in Drift.
- Channel unread counters are part of the volatile sidebar snapshot and are
  never persisted locally.
- Refresh keeps list identity and scroll position where possible.
- User-facing strings come from the feature's string layer, not widgets.
- Keyboard traversal, focus restoration, semantics, touch targets, and large
  text remain part of the sidebar contract.

## Relevant code

- `lib/src/features/channel_members/`
- `lib/src/ui/channels/`
- `lib/src/ui/shell/shell_page.dart`
- `lib/src/data/mappers/channel_sidebar_mapper.dart`
- `lib/src/data/repositories/mattermost_channel_repository.dart`
