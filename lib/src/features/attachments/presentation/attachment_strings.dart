abstract final class AttachmentStrings {
  static const String attachments = 'Attachments';
  static const String close = 'Close';
  static const String download = 'Download';
  static const String downloadFailed = 'Could not download the file.';
  static const String downloadSucceeded = 'File saved.';
  static const String imageLoadFailed = 'Could not load image';
  static const String nextImage = 'Next image';
  static const String previousImage = 'Previous image';

  static String imagePosition(int current, int total) => '$current of $total';
}
