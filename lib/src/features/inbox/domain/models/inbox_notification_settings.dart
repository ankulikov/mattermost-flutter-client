/// Desktop notification levels that can affect Inbox membership.
///
/// [inherit] is a channel-level `default` (or an omitted override). [unknown]
/// preserves an unrecognised wire value so policies can choose a conservative
/// fallback instead of treating a future server value as `all`.
enum InboxDesktopNotificationLevel { all, mention, none, inherit, unknown }

/// The channel unread mode relevant to ordinary all-activity posts.
enum InboxMarkUnread { all, mention, unknown }

/// Inbox-relevant notification settings owned by a user.
final class InboxUserNotificationSettings {
  const InboxUserNotificationSettings({
    this.desktop = InboxDesktopNotificationLevel.unknown,
    this.desktopThreads = InboxDesktopNotificationLevel.unknown,
  });

  final InboxDesktopNotificationLevel desktop;
  final InboxDesktopNotificationLevel desktopThreads;
}

/// Inbox-relevant notification overrides owned by a channel membership.
final class InboxChannelNotificationSettings {
  const InboxChannelNotificationSettings({
    this.desktop = InboxDesktopNotificationLevel.inherit,
    this.desktopThreads = InboxDesktopNotificationLevel.inherit,
    this.markUnread = InboxMarkUnread.unknown,
  });

  final InboxDesktopNotificationLevel desktop;
  final InboxDesktopNotificationLevel desktopThreads;
  final InboxMarkUnread markUnread;
}
