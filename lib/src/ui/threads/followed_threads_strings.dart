import 'package:mattermost_flutter/src/ui/messages/thread_summary_strings.dart';

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
  static const String now = 'now';

  static String replies(int count) => ThreadSummaryStrings.replies(count);
  static String unreadReplies(int count) =>
      ThreadSummaryStrings.unreadReplies(count);
  static String newReplies(int count) => ThreadSummaryStrings.newReplies(count);
  static String mentions(int count) => ThreadSummaryStrings.mentions(count);
  static String additionalParticipants(int count) =>
      ThreadSummaryStrings.additionalParticipants(count);
  static String minutesAgo(int count) =>
      count == 1 ? '1 minute ago' : '$count minutes ago';
  static String hoursAgo(int count) =>
      count == 1 ? '1 hour ago' : '$count hours ago';
}
