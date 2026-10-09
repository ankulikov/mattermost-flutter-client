import 'package:mattermost_flutter/src/ui/messages/widgets/file_attachment_presentation.dart';

abstract final class MessageComposerStrings {
  static const String send = 'Send message';
  static const String sending = 'Sending message';
  static const String sendFailed =
      'Message could not be sent. Your draft has been kept.';
  static const String attach = 'Attach files';
  static const String removeFile = 'Remove file';
  static const String retryUpload = 'Retry upload';
  static const String uploadReady = 'Ready';
  static const String uploadFinalizing = 'Finalizing upload…';
  static const String uploadQueued = 'Waiting to upload';
  static const String tooManyFiles = 'Choose up to five files per message.';
  static const String pickerFailed = 'Files could not be selected.';
  static const String uploadFailed = 'Upload failed';
  static const String fileTooLarge = 'File exceeds the server size limit';
  static const String uploadForbidden = 'Uploading is not allowed here';
  static const String signInAgain = 'Sign in again to upload';
  static const String retryLater = 'Server is busy. Retry shortly';
  static const String invalidFile = 'File size is unavailable';
  static String fileDetails(String? type, int size) =>
      '${type ?? 'File'} · ${formatAttachmentFileSize(size)}';

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
