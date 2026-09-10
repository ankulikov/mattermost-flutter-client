abstract final class ShellStrings {
  static const String appTitle = 'Mattermost';
  static const String channels = 'Channels';
  static const String inbox = 'Inbox';
  static const String profile = 'Profile';
  static const String inboxHasNewMessages = 'Inbox has new messages';
  static const String openInbox = 'Open Inbox';
  static const String newInboxMessage = 'New Inbox message';

  static String inboxNotification({
    required String author,
    required String channel,
    required String message,
  }) {
    final String normalized = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    final String preview = normalized.isEmpty
        ? newInboxMessage
        : normalized.length <= 140
        ? normalized
        : '${normalized.substring(0, 139)}…';
    return '$author · $channel\n$preview';
  }
}
