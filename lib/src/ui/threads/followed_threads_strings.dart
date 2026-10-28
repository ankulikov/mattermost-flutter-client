abstract final class FollowedThreadsStrings {
  static const String title = 'Threads';
  static const String subtitle =
      'Threads you participate in or follow appear here';
  static const String loading = 'Loading threads';
  static const String empty = 'No followed threads yet';
  static const String loadFailed = 'Could not load threads';
  static const String refreshFailed =
      'Could not refresh. Showing previously loaded threads.';
  static const String retry = 'Retry';
  static const String loadMore = 'Load more threads';
  static const String loadingMore = 'Loading more threads';
  static const String refresh = 'Refresh threads';
  static const String noTeam = 'Select a team to see followed threads';

  static String replies(int count) => count == 1 ? '1 reply' : '$count replies';
  static String unreadReplies(int count) =>
      count == 1 ? '1 unread reply' : '$count unread replies';
  static String mentions(int count) =>
      count == 1 ? '1 unread mention' : '$count unread mentions';
  static String rowLabel({
    required String author,
    required String context,
    required int unreadReplies,
  }) =>
      '$author, $context, ${unreadReplies > 0 ? FollowedThreadsStrings.unreadReplies(unreadReplies) : 'Read thread'}';
}
