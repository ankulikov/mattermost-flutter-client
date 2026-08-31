abstract final class ThreadStrings {
  static const String title = 'Thread';
  static const String close = 'Close thread';
  static const String loading = 'Loading thread';
  static const String loadFailed = 'Could not refresh this thread';
  static const String missingRoot = 'The original message is unavailable';
  static const String deletedMessage = 'This message was deleted';
  static const String reactions = 'Reactions';
  static const String reactionFailed = 'Could not update the reaction.';
  static const String retry = 'Retry';
  static const String replies = 'Replies';
  static const String unreadMessages = 'unread messages';
  static const String markReadFailed = 'Could not mark this thread as read';

  static String replyCount(int count) =>
      count == 1 ? '1 reply' : '$count replies';
  static String lastReply(String time) => 'Last reply $time';
}
