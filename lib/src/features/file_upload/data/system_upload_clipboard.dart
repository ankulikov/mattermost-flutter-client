import 'dart:typed_data';

import 'package:mattermost_flutter/src/features/file_upload/data/clipboard_file_sources.dart'
    if (dart.library.io) 'package:mattermost_flutter/src/features/file_upload/data/clipboard_file_sources_io.dart'
    as file_sources;
import 'package:mattermost_flutter/src/features/file_upload/domain/file_upload.dart';
import 'package:pasteboard/pasteboard.dart';

/// Adapts copied files and images to the same upload sources as the picker.
final class SystemUploadClipboard implements UploadClipboard {
  const SystemUploadClipboard();

  @override
  Future<List<SelectedUploadFile>> readFiles() async {
    final List<SelectedUploadFile> files = await file_sources.readCopiedFiles();
    if (files.isNotEmpty) return files;

    final Uint8List? image = await Pasteboard.image;
    if (image == null || image.isEmpty) return const <SelectedUploadFile>[];
    return <SelectedUploadFile>[
      SelectedUploadFile(
        name: clipboardImageName(DateTime.now(), 'png'),
        size: image.length,
        type: 'png',
        openStream: () => Stream<Uint8List>.value(image),
      ),
    ];
  }
}
