import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_notification_settings.dart';

/// Resolves a channel desktop override against the user's desktop setting.
///
/// Missing and unknown inherited values intentionally resolve to [mention].
/// This avoids silently subscribing a user to every post when a server adds an
/// unsupported notification value.
InboxDesktopNotificationLevel resolveInboxDesktopNotificationLevel({
  required InboxDesktopNotificationLevel channel,
  required InboxDesktopNotificationLevel user,
}) => switch (channel) {
  InboxDesktopNotificationLevel.all ||
  InboxDesktopNotificationLevel.mention ||
  InboxDesktopNotificationLevel.none => channel,
  InboxDesktopNotificationLevel.inherit => switch (user) {
    InboxDesktopNotificationLevel.all ||
    InboxDesktopNotificationLevel.mention ||
    InboxDesktopNotificationLevel.none => user,
    InboxDesktopNotificationLevel.inherit ||
    InboxDesktopNotificationLevel.unknown =>
      InboxDesktopNotificationLevel.mention,
  },
  InboxDesktopNotificationLevel.unknown =>
    InboxDesktopNotificationLevel.mention,
};

/// Returns whether a channel's effective desktop setting opts it into the
/// Inbox all-messages source.
bool resolvesToAllMessagesSubscription({
  required InboxChannelNotificationSettings channel,
  required InboxUserNotificationSettings user,
}) {
  return channel.markUnread == InboxMarkUnread.all &&
      resolveInboxDesktopNotificationLevel(
            channel: channel.desktop,
            user: user.desktop,
          ) ==
          InboxDesktopNotificationLevel.all;
}

/// Returns whether a DM or GM can contribute an Inbox source.
///
/// Direct attention is included for `all` and `mention`; `none` is the only
/// explicit exclusion. The source-specific unread and self-post checks remain
/// the caller's responsibility.
bool isDirectMessageInboxEligible({
  required InboxChannelNotificationSettings channel,
  required InboxUserNotificationSettings user,
}) =>
    resolveInboxDesktopNotificationLevel(
      channel: channel.desktop,
      user: user.desktop,
    ) !=
    InboxDesktopNotificationLevel.none;

/// Returns whether unread activity in a followed thread belongs in Inbox.
///
/// An explicit `desktop=none` channel setting is a hard gate. Otherwise,
/// `desktop_threads=all` includes every unread reply, while `mention` includes
/// only server-counted unread mentions. Unknown values fall back to `mention`.
bool isFollowedThreadInboxEligible({
  required InboxChannelNotificationSettings channel,
  required InboxUserNotificationSettings user,
  required int unreadReplies,
  required int unreadMentions,
}) {
  if (resolveInboxDesktopNotificationLevel(
        channel: channel.desktop,
        user: user.desktop,
      ) ==
      InboxDesktopNotificationLevel.none) {
    return false;
  }

  return switch (resolveInboxDesktopNotificationLevel(
    channel: channel.desktopThreads,
    user: user.desktopThreads,
  )) {
    InboxDesktopNotificationLevel.all => unreadReplies > 0,
    InboxDesktopNotificationLevel.mention => unreadMentions > 0,
    InboxDesktopNotificationLevel.none => false,
    InboxDesktopNotificationLevel.inherit ||
    InboxDesktopNotificationLevel.unknown => unreadMentions > 0,
  };
}
