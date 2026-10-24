import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mattermost_flutter/src/features/file_upload/domain/file_upload.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;

const MethodChannel _macClipboard = MethodChannel('mattermost/clipboard_files');

Future<List<SelectedUploadFile>> readCopiedFiles() async {
  if (!Platform.isMacOS) return fromPaths(await Pasteboard.files());
  final List<Object?>? copied = await _macClipboard.invokeListMethod<Object?>(
    'pasteFiles',
  );
  if (copied == null || copied.isEmpty) return const <SelectedUploadFile>[];
  final List<SelectedUploadFile> files = <SelectedUploadFile>[];
  for (final Object? entry in copied) {
    if (entry is! Map<Object?, Object?>) continue;
    final String? path = entry['path'] as String?;
    final String? name = entry['name'] as String?;
    if (path == null || name == null || name.isEmpty) continue;
    final File file = File(path);
    files.add(
      SelectedUploadFile(
        name: name,
        size: await file.length(),
        type: p.extension(name).replaceFirst('.', ''),
        openStream: () => file.openRead().map(Uint8List.fromList),
        dispose: () => unawaited(
          _macClipboard
              .invokeMethod<void>('releaseFile', path)
              .catchError((Object _) {}),
        ),
      ),
    );
  }
  return files;
}

Future<List<SelectedUploadFile>> fromPaths(List<String> paths) async {
  final List<SelectedUploadFile> files = <SelectedUploadFile>[];
  for (final String path in paths.take(6)) {
    // Android clipboard entries can be content:// URIs, not local paths.
    // The image representation is read separately when no path is usable.
    if (!p.isAbsolute(path)) continue;
    final File file = File(path);
    int size;
    try {
      size = await file.length();
    } on FileSystemException {
      size = -1;
    }
    final String name = p.basename(path);
    if (name.isEmpty) continue;
    files.add(
      SelectedUploadFile(
        name: name,
        size: size,
        type: p.extension(name).replaceFirst('.', ''),
        openStream: () => file.openRead().map(Uint8List.fromList),
      ),
    );
  }
  return files;
}
