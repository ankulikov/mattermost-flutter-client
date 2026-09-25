abstract final class MessageComposerStrings {
  static const String send = 'Send message';
  static const String sending = 'Sending message';
  static const String sendFailed =
      'Message could not be sent. Your draft has been kept.';

  static const String formattingToolbar = 'Message formatting';
  static const String moreFormatting = 'More formatting options';
  static const String formatBold = 'Bold';
  static const String formatItalic = 'Italic';
  static const String formatStrike = 'Strikethrough';
  static const String formatHeading = 'Heading';
  static const String formatCode = 'Code';
  static const String formatQuote = 'Quote';
  static const String formatBulletedList = 'Bulleted list';
  static const String formatOrderedList = 'Numbered list';

  static String emojiSuggestions(String query) =>
      'Emoji suggestions for :$query';

  static String channelPlaceholder(String channelName) =>
      'Message #$channelName';

  static const String replyPlaceholder = 'Reply…';
}
