import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:mattermost_flutter/src/domain/repositories/attachment_repository.dart';
import 'package:path/path.dart' as p;

final class SystemAttachmentFileSaver implements AttachmentFileSaver {
  const SystemAttachmentFileSaver();

  @override
  Future<bool> save({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final String safeFileName = p.basename(fileName);
    final String extension = p.extension(safeFileName).replaceFirst('.', '');
    final String stem = extension.isEmpty
        ? safeFileName
        : p.basenameWithoutExtension(safeFileName);
    final String? savedPath = await FileSaver.instance.saveAs(
      name: stem.isEmpty ? 'attachment' : stem,
      bytes: bytes,
      fileExtension: extension,
      includeExtension: extension.isNotEmpty,
      mimeType: MimeType.custom,
      customMimeType: mimeType.isEmpty ? 'application/octet-stream' : mimeType,
    );
    return savedPath != null;
  }
}
