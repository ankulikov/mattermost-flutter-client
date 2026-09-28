# Channels and sidebar

The sidebar is a network-first view of the current team, channel categories,
channels, and direct conversations. Its controller owns the snapshot only while
the authenticated shell is using it.

## Loading and refresh

The initial request loads the user's first team, its channels, and sidebar
categories. Direct and group-message names are resolved through the users API.
An initial failure shows a retry state. Manual refresh keeps the existing
snapshot visible until the replacement succeeds and reports a non-blocking
failure otherwise.

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

## Adaptive shell

Compact layouts show Channels and Inbox as separate destinations with bottom
navigation. Medium and expanded layouts keep a navigation rail visible. The
left pane shows either the channel list or the Inbox; an Inbox selection does
not leave an unrelated channel list beside it. Expanded layouts can keep that
left pane visible while a message or thread opens in the working area.

The shell, sidebar, and panes choose their layout from constraints. No feature
branches on mobile versus desktop to select a layout.

## State rules

- Sidebar snapshots, category expansion, pagination state, and sync metadata
  are not stored in Drift.
- Refresh keeps list identity and scroll position where possible.
- User-facing strings come from the feature's string layer, not widgets.
- Keyboard traversal, focus restoration, semantics, touch targets, and large
  text remain part of the sidebar contract.

## Relevant code

- `lib/src/ui/channels/`
- `lib/src/ui/shell/shell_page.dart`
- `lib/src/data/mappers/channel_sidebar_mapper.dart`
- `lib/src/data/repositories/mattermost_channel_repository.dart`
