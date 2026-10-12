abstract final class MessageActionsStrings {
  static const String actions = 'Message actions';
  static const String addReaction = 'Add reaction';
  static const String save = 'Save message';
  static const String more = 'More actions';
  static const String markUnread = 'Mark as unread';
  static const String postpone = 'Postpone task';
  static const String postponed = 'Task added to Postponed';
  static const String postponeFailed = 'Could not postpone the task.';
  static const String copyLink = 'Copy link';
  static const String linkCopied = 'Link copied';
  static const String copyText = 'Copy text';
  static const String quote = 'Quote';
  static const String pinToChannel = 'Pin to channel';
  static const String edit = 'Edit';
  static const String delete = 'Delete';
  static const String deleteFailed = 'Could not delete the message.';
  static const String searchEmojis = 'Search emojis';
  static const String recentlyUsed = 'Recently used';
  static const String smileysAndEmotion = 'Smileys & emotion';
  static const String peopleAndBody = 'People & body';
  static const String animalsAndNature = 'Animals & nature';
  static const String foodAndDrink = 'Food & drink';
  static const String travelAndPlaces = 'Travel & places';
  static const String activities = 'Activities';
  static const String objects = 'Objects';
  static const String symbols = 'Symbols';
  static const String flags = 'Flags';
  static const String customEmoji = 'Custom emoji';
  static const String noEmojis = 'No emojis to show.';
  static const String customEmojiLoadFailed = 'Could not load custom emojis.';
  static const String customEmojiSearchFailed =
      'Custom emoji search is unavailable.';
  static const String retry = 'Retry';

  static String noEmojiResults(String term) => 'No emojis found for “$term”.';

  static String reactionPeople(String names, String emoji) =>
      '$names\nreacted with $emoji';

  static String reactionCount(int count, String emoji) =>
      '$count ${count == 1 ? 'person' : 'people'} reacted with $emoji';
}
