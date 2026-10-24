import 'dart:typed_data';

import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';

/// Names clipboard images when the source does not provide a filename.
String clipboardImageName(DateTime now, String extension) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return 'clipboard_${now.year}_${twoDigits(now.month)}_'
      '${twoDigits(now.day)}_${twoDigits(now.hour)}_'
      '${twoDigits(now.minute)}_${twoDigits(now.second)}.$extension';
}

/// A picker-owned source which can open a new stream for every upload attempt.
final class SelectedUploadFile {
  const SelectedUploadFile({
    required this.name,
    required this.size,
    required this.openStream,
    this.type,
    this.dispose,
  });

  final String name;
  final int size;
  final String? type;
  final Stream<Uint8List> Function() openStream;
  final void Function()? dispose;
}

abstract interface class UploadFilePicker {
  Future<List<SelectedUploadFile>> pickFiles();
}

/// Reads file content from the system clipboard for the active composer.
abstract interface class UploadClipboard {
  Future<List<SelectedUploadFile>> readFiles();
}

enum UploadFailure {
  tooLarge,
  unauthorized,
  forbidden,
  rateLimited,
  unavailable,
  invalidFile,
}

final class UploadException implements Exception {
  const UploadException(this.failure, {this.retryAfter});

  final UploadFailure failure;
  final Duration? retryAfter;
}

abstract interface class FileUploadRepository {
  Future<String> upload({
    required String channelId,
    required SelectedUploadFile file,
    required RequestCancellation cancellation,
    required void Function(int sent, int total) onProgress,
  });
}
