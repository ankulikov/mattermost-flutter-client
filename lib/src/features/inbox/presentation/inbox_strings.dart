import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_completeness.dart';

abstract final class InboxStrings {
  static const String title = 'Inbox';
  static const String newItems = 'New';
  static const String postponed = 'Postponed';
  static const String loading = 'Loading Inbox';
  static const String loadFailed = 'Could not load Inbox';
  static const String refreshFailed =
      'Could not refresh. Showing previously loaded Inbox.';
  static const String completenessExact = 'Inbox coverage is complete.';
  static const String completenessApproximateMentions =
      'Some historical mentions may be missing.';
  static const String completenessTruncated =
      'Some Inbox sources could not be fully loaded.';
  static const String followedThreadsSourceFailed =
      'Followed threads could not be loaded.';
  static const String unreadChannelPostsSourceFailed =
      'Unread channel posts could not be loaded.';
  static const String postponedSourceFailed =
      'Postponed items could not be loaded.';
  static const String retry = 'Retry';
  static const String retryInbox = 'Retry loading Inbox';
  static const String retryInboxSettings = 'Retry loading Inbox settings';
  static const String retrySaveInboxSettings = 'Retry saving Inbox settings';
  static const String retryFollowedThreads = 'Retry loading followed threads';
  static const String retryUnreadChannelPosts =
      'Retry loading unread channel posts';
  static const String retryPostponed = 'Retry loading postponed items';
  static const String refresh = 'Refresh Inbox';
  static const String settings = 'Inbox settings';
  static const String openSettings = 'Open Inbox settings';
  static const String settingsTitle = 'Inbox settings';
  static const String settingsLoading = 'Loading Inbox settings';
  static const String settingsLoadFailed = 'Could not load Inbox settings';
  static const String settingsSave = 'Save settings';
  static const String settingsSaving = 'Saving settings';
  static const String settingsSaveFailed =
      'Could not save changes. Your selections are still available.';
  static const String desktopPolicyTitle = 'Desktop notifications';
  static const String desktopPolicyDescription =
      'Mattermost desktop notification settings remain authoritative. Inbox settings can only narrow what is shown.';
  static const String desktopPolicySemantics =
      'Desktop notification policy is authoritative and read only.';
  static const String settingsEnabled = 'Enable Inbox';
  static const String settingsEnabledDescription =
      'Show the Inbox projection and its badge.';
  static const String settingsSourcesTitle = 'Sources';
  static const String settingsDirectMessages = 'Direct messages';
  static const String settingsGroupMessages = 'Group messages';
  static const String settingsMentions = 'Mentions';
  static const String settingsFollowedThreads = 'Followed threads';
  static const String settingsAllActivity = 'All activity';
  static const String settingsAllActivityDescription =
      'Ordinary channel posts allowed by desktop notifications.';
  static const String settingsAutomations = 'Automations';
  static const String settingsAutomationInclude = 'Include';
  static const String settingsAutomationExclude = 'Exclude';
  static const String settingsAutomationSeparate = 'Show separately';
  static const String settingsBehaviorTitle = 'Behavior';
  static const String settingsForegroundNotifications =
      'Foreground notifications';
  static const String settingsShowMessagePreview = 'Show message previews';
  static const String settingsShowMessagePreviewDescription =
      'Include message text in foreground Inbox notifications.';
  static const String settingsReactivateOnMention =
      'Reactivate postponed threads on mention';
  static const String settingsReactivateOnMentionDescription =
      'Return a postponed thread to New when it receives an explicit mention.';
  static const String settingsRemoveOnOpen = 'Remove postponed items on open';
  static const String settingsRemoveOnOpenDescription =
      'Treat opening a postponed item as completing it.';
  static const String settingsDirectGrouping = 'Direct message grouping';
  static const String settingsGroupingNone = 'Do not group';
  static const String settingsGroupingConsecutive = 'Consecutive messages';
  static const String settingsGroupingConversation = 'By conversation';
  static const String connecting = 'Inbox realtime is connecting';
  static const String connected = 'Inbox realtime is connected';
  static const String disconnected = 'Inbox realtime is disconnected';
  static const String emptyNew = 'No new messages';
  static const String emptyPostponed = 'No postponed messages';
  static const String read = 'Mark as read';
  static const String postpone = 'Postpone';
  static const String remove = 'Remove';
  static const String openItemHint = 'Open message details';
  static const String unavailablePostponedTitle = 'Unavailable postponed item';
  static const String unavailablePostponedBody =
      'This postponed message is no longer available.';
  static const String unavailablePostponedSemantics =
      'Unavailable postponed item. Remove is available.';
  static const String markReadFailed = 'Could not mark this item as read.';
  static const String postponeFailed = 'Could not postpone this item.';
  static const String removeFailed = 'Could not remove this item.';
  static const String mentions = 'Mentions';
  static const String allActivity = 'All activity';
  static const String bots = 'Bots & integrations';
  static const String directMessages = 'Direct Messages';
  static const String threads = 'Threads';
  static const String thread = 'Thread';
  static String tabWithMessageCount(String tab, int count) =>
      '$tab, ${messages(count)}';
  static String completeness(InboxCompleteness value) => switch (value) {
    InboxCompleteness.exact => completenessExact,
    InboxCompleteness.approximateMentions => completenessApproximateMentions,
    InboxCompleteness.truncated => completenessTruncated,
  };
  static String sourceFailure(InboxSourceScope scope) => switch (scope) {
    InboxSourceScope.followedThreads => followedThreadsSourceFailed,
    InboxSourceScope.unreadChannelPosts => unreadChannelPostsSourceFailed,
    InboxSourceScope.postponed => postponedSourceFailed,
  };
  static String retrySource(InboxSourceScope scope) => switch (scope) {
    InboxSourceScope.followedThreads => retryFollowedThreads,
    InboxSourceScope.unreadChannelPosts => retryUnreadChannelPosts,
    InboxSourceScope.postponed => retryPostponed,
  };
  static String itemSemantics(String title, String body) => '$title. $body';
  static String messages(int count) =>
      count == 1 ? '1 message' : '$count messages';
  static String sectionWithMessageCount(String section, int count) =>
      '$section, ${messages(count)}';
  static String replies(int count) => count == 1 ? '1 reply' : '$count replies';
}
