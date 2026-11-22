abstract final class ThreadSummaryStrings {
  static String replies(int count) => count == 1 ? '1 reply' : '$count replies';
  static String unreadReplies(int count) =>
      count == 1 ? '1 unread reply' : '$count unread replies';
  static String newReplies(int count) =>
      count == 1 ? '1 new reply' : '$count new replies';
  static String mentions(int count) =>
      count == 1 ? '1 unread mention' : '$count unread mentions';
  static String additionalParticipants(int count) => count == 1
      ? '1 additional participant'
      : '$count additional participants';
}
