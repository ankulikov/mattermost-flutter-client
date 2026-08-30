import 'dart:typed_data';

enum AttachmentVariant { thumbnail, preview, original }

final class AttachmentContent {
  const AttachmentContent({required this.bytes, this.contentType});

  final Uint8List bytes;
  final String? contentType;
}
