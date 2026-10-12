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
  static const String read = 'Done';
  static const String postpone = 'Postpone';
  static const String remove = 'Remove';
  static const String markReadFailed = 'Could not mark this item as read.';
  static const String postponeFailed = 'Could not postpone this item.';
  static const String removeFailed = 'Could not remove this item.';
  static const String directMessage = 'Direct message';
  static const String updates = 'Updates';
  static const String mentioned = 'mentioned';
  static const String you = 'You';
  static const String mention = 'Mention';
  static const String channelMention = '@channel';
  static const String newPostInChannel = 'New post in a channel';
  static const String groupMentionFallback = 'Group mention';
  static String messagesSince(int count) =>
      '${count == 1 ? 'message' : 'messages'} since';
  static String newRepliesWithLastOneAt(int count) =>
      '${count == 1 ? 'new reply' : 'new replies'}, last one at';
  static String tabWithMessageCount(String tab, int count) =>
      '$tab, ${messages(count)}';
  static String messages(int count) =>
      count == 1 ? '1 message' : '$count messages';
  static String replies(int count) => count == 1 ? '1 reply' : '$count replies';
}
