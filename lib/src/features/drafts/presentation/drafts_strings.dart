abstract final class DraftsStrings {
  static const syncUnavailable =
      'Draft sync is unavailable; drafts are kept for this session.';
  static const title = 'Drafts';
  static const empty = 'No drafts yet';
  static const loading = 'Loading drafts';
  static const loadFailed = 'Could not load drafts';
  static const refreshFailed = 'Could not refresh drafts';
  static const retry = 'Retry';
  static const refresh = 'Refresh drafts';
  static const edit = 'Edit';
  static const delete = 'Delete';
  static const send = 'Send';
  static const thread = 'Thread';
  static const unsynced = 'Not synced';
  static String attachments(int count) => '$count attachment(s)';
  static const sendFailed = 'Could not send draft';
  static const cleanupPending = 'Sent · cleanup pending';
  static const unsupportedOptions = 'This draft has unsupported send options';
  static const syncFailed = 'Could not sync draft';
}
