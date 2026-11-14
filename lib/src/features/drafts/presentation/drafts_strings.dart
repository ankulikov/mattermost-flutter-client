abstract final class DraftsStrings {
  static const syncUnavailable =
      'Draft sync is unavailable; drafts are kept for this session.';
  static const title = 'Drafts';
  static const subtitle = "Any messages you've started will show here";
  static const empty = 'No drafts yet';
  static const loading = 'Loading drafts';
  static const loadFailed = 'Could not load drafts';
  static const refreshFailed = 'Could not refresh drafts';
  static const retry = 'Retry';
  static const edit = 'Edit';
  static const delete = 'Delete';
  static const deleteTitle = 'Delete draft';
  static String deleteConfirmation(String destination) =>
      'Are you sure you want to delete this draft to $destination?';
  static const cancel = 'Cancel';
  static const confirmDelete = 'Yes, delete';
  static const send = 'Send';
  static const thread = 'Thread';
  static const unsynced = 'Not synced';
  static String attachments(int count) => '$count attachment(s)';
  static const sendFailed = 'Could not send draft';
  static const cleanupPending = 'Sent · cleanup pending';
  static const unsupportedOptions = 'This draft has unsupported send options';
  static const syncFailed = 'Could not sync draft';
}
