abstract final class InboxStrings {
  static const String title = 'Inbox';
  static const String newItems = 'New';
  static const String postponed = 'Postponed';
  static const String loading = 'Loading Inbox';
  static const String loadFailed = 'Could not load Inbox';
  static const String refreshFailed =
      'Could not refresh. Showing previously loaded Inbox.';
  static const String retry = 'Retry';
  static const String refresh = 'Refresh Inbox';
  static const String connecting = 'Inbox realtime is connecting';
  static const String connected = 'Inbox realtime is connected';
  static const String disconnected = 'Inbox realtime is disconnected';
  static const String emptyNew = 'No new messages';
  static const String emptyPostponed = 'No postponed messages';
  static const String read = 'Read';
  static const String postpone = 'Postpone';
  static const String remove = 'Remove';
  static const String markReadFailed = 'Could not mark this item as read.';
  static const String postponeFailed = 'Could not postpone this item.';
  static const String removeFailed = 'Could not remove this item.';
  static const String directMessage = 'Direct message';
  static const String groupMentionFallback = 'Group mention';
  static String threadInChannel(String channelName) => 'Thread in $channelName';
  static String groupMentionInChannel(String groupTag, String channelName) =>
      '$groupTag in $channelName';
  static String youMentionedInChannel(String channelName) =>
      'You mentioned in $channelName';
  static String unreadMessages(int count) =>
      count == 1 ? '1 unread message' : '$count unread messages';
  static String tabWithMessageCount(String tab, int count) =>
      '$tab, ${messages(count)}';
  static String messages(int count) =>
      count == 1 ? '1 message' : '$count messages';
  static String replies(int count) => count == 1 ? '1 reply' : '$count replies';
}
