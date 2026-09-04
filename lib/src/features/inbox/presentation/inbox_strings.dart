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
  static const String emptyNew = 'No new messages';
  static const String emptyPostponed = 'No postponed messages';
  static const String open = 'Open';
  static const String postpone = 'Postpone';
  static const String remove = 'Remove';
  static const String people = 'People';
  static const String bots = 'Bots & integrations';
  static const String thread = 'Thread';
  static String messages(int count) =>
      count == 1 ? '1 message' : '$count messages';
  static String replies(int count) => count == 1 ? '1 reply' : '$count replies';
}
