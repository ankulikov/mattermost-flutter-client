# Channels and sidebar

The sidebar is a network-first view of the current team, channel categories,
channels, and direct conversations. Its controller owns the snapshot only while
the authenticated shell is using it.

## Loading and refresh

The initial request loads the user's first team, its channels, channel
memberships, and sidebar categories. Membership read counters are compared with
the channel totals: ordinary channels use the CRT root counters, while direct
and group conversations use the full-message counters. Unmuted unread channels
use a dot and an emphasized icon; their names keep the regular weight. Muted
channels retain the muted treatment.

Unread state is updated from `posted`, `channel_viewed`, and `post_unread`
WebSocket events. A reconnect or sequence gap performs an authoritative REST
reload. There is no polling interval: the sidebar loads when its session starts,
updates from realtime events, and reloads on manual refresh or realtime
recovery. Selecting a channel calls the v4 channel-view endpoint and clears the
local highlight after the server accepts the new read boundary.

Direct and group-message names are resolved through the users API. An initial
failure shows a retry state. Manual refresh keeps the existing snapshot visible
until the replacement succeeds and reports a non-blocking failure otherwise.
Direct-user identity is fetched fresh with the sidebar so the server's `is_bot`
flag can move bot DMs out of Direct messages into the local Боты section.
Favorites and custom server categories keep their channels. The virtual section
can collapse locally and never writes a Mattermost category.

Collapsing a server category updates its collapse state through the v4
single-category endpoint. If an update fails, the local choice remains usable
and the sidebar reports that it could not be synchronized. Collapsed categories
continue to display unmuted unread channels and the selected channel. Muted
categories expose unread mentions when collapsed; ordinary unread activity
remains hidden unless the channel is selected. Synthetic uncategorized sections
keep their expansion state locally.

Sidebar search filters the loaded snapshot locally by the displayed channel or
conversation name. Matches remain in their original categories. Search expands
matching categories temporarily and restores their previous expansion state
when the query is cleared. Threads is hidden while a non-blank channel search
query is active and returns when the query is cleared.
The search field expands into the adjacent filter button's space while focused,
without moving the list vertically. The button locally hides read channels and
dialogs. Muted channels and channels in muted categories stay hidden for ordinary
unread activity, but server-reported unread mentions remain visible. Search
respects the active filter. Categories with no visible channels,
including categories that were empty before filtering, are hidden. The filter
is saved per account and restored before the sidebar list appears.
A second local button hides folder headings and shows their channels as one
ordered list, including channels in collapsed folders. Showing the headings
again restores the previous collapse state without changing server categories.
This choice is also saved per account. Both choices use local
`SharedPreferencesAsync`; sidebar snapshots and unread counters remain volatile.

Channel and category rows use a compact 40 px minimum interactive height to
fit more entries on screen. Rows can grow when text scaling requires more room.
Search uses an inset, rounded field with an outline and at least a 40 px target.
Channel and Threads selection and hover use the same inset and rounded surfaces
while icons and text stay aligned with the sidebar grid.
Category headers use that inset and rounded hover surface, with a small leading
chevron and an uppercase compact label. Search, Threads, and channel names use
13 px text; direct-message avatars are smaller to leave space before names.
Unmuted unread channels show a small dot immediately after the name.
Favorites stay at the top of the sidebar regardless of the server's category
order. A small star identifies each favorite even when folder headings are
hidden. Favorites remain visible when the read-channel filter is active;
typed search terms still narrow them by name.
Right-clicking a channel row (or using a trackpad secondary click, long press,
or the keyboard context-menu shortcut) opens its actions: mark unread, change
favorites, mute or unmute, and move to a sidebar category. Direct and group
conversations also offer Close conversation, which hides that conversation for
the current user without deleting its messages. These actions persist through
Mattermost API v4 and refresh the network-first sidebar after success; failures
leave the current list usable and show an error.
Public and private channels offer a final Leave channel action. It asks for
confirmation, warns that private channels require a new invitation to rejoin,
then removes the current user's channel membership. Town Square omits this
action because Mattermost does not allow members to leave its default channel.

## Direct-message avatars

The users batch response supplies a versioned profile reference for each direct
conversation. Visible rows render initials immediately, then request
authenticated avatar bytes through `UserRepository`. Sidebar rows, messages,
and profile cards share the same account-scoped cache and in-flight request.

Mattermost does not expose a separate avatar thumbnail endpoint. The UI limits
decode size for the rendered control. A failed image request leaves the initials
in place and does not block navigation.

Direct-message avatars show the participant's availability from a batched
`POST /users/status/ids` request. `status_change` WebSocket events update the
open sidebar; reconnect or a sequence gap reloads the server state. A failed
status request leaves conversations usable and labels presence as unavailable,
rather than claiming the user is offline. Status labels are exposed to assistive
technology and in a tooltip.

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
navigation. Medium and expanded channel layouts align the sidebar, channel,
and thread headers in one row. Icon-only Channels and Inbox controls precede
the team name in the sidebar header. A divider separates the scrollable channel
list from the current-user avatar button pinned to the bottom of the left pane.
Other destinations use a global header. Both icon controls have tooltips and
semantic labels, and Inbox keeps its new-item indicator. The left pane shows
either the channel list or the Inbox; an Inbox selection does not leave an
unrelated channel list beside it. Expanded layouts can keep that left pane
visible while a message or thread opens in the working area.

The shell, sidebar, and panes choose their layout from constraints. No feature
branches on mobile versus desktop to select a layout.

On medium and expanded layouts, the divider between the channel list and working
area can be dragged or adjusted with the left and right arrow keys. Its width
stays within 200–500 px and leaves at least 320 px for the working area. The
chosen width remains in shell view state while destinations change and is
clamped when the window narrows.

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
