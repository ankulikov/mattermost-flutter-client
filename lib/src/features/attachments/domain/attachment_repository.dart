import 'dart:typed_data';

import 'package:mattermost_flutter/src/features/messages/domain/message.dart';

enum AttachmentVariant { thumbnail, preview, original }

final class AttachmentContent {
  const AttachmentContent({required this.bytes, this.contentType});

  final Uint8List bytes;
  final String? contentType;
}

abstract interface class AttachmentRepository {
  Future<AttachmentContent> load({
    required String fileId,
    required AttachmentVariant variant,
  });

  /// Returns false when the user dismisses the platform save dialog.
  Future<bool> download(PostAttachment attachment);
}

abstract interface class AttachmentFileSaver {
  /// Returns false when the user dismisses the platform save dialog.
  Future<bool> save({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  });
}
