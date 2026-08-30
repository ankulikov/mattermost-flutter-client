import 'dart:typed_data';

import 'package:mattermost_flutter/src/domain/models/attachment.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';

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
