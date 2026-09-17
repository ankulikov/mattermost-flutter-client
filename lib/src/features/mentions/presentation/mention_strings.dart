abstract final class MentionStrings {
  static const String channelMembers = 'Channel members';
  static const String groupMentions = 'Group Mentions';
  static const String notInChannel = 'Not in channel';
  static const String noMatches = 'No matching people or groups';
  static const String suggestionsFailed = 'Could not load mention suggestions.';
  static const String retry = 'Retry';
  static const String dismiss = 'Dismiss';

  static String groupMemberCount(int count) =>
      '$count ${count == 1 ? 'member' : 'members'}';
}
