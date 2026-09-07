abstract final class MessageComposerStrings {
  static const String send = 'Send message';
  static const String sending = 'Sending message';
  static const String sendFailed =
      'Message could not be sent. Your draft has been kept.';

  static String emojiSuggestions(String query) =>
      'Emoji suggestions for :$query';

  static String channelPlaceholder(String channelName) =>
      'Message #$channelName';

  static const String replyPlaceholder = 'Reply…';
}
