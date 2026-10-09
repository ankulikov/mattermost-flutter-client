import 'dart:typed_data';

import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';

/// A picker-owned source which can open a new stream for every upload attempt.
final class SelectedUploadFile {
  const SelectedUploadFile({
    required this.name,
    required this.size,
    required this.openStream,
    this.type,
  });

  final String name;
  final int size;
  final String? type;
  final Stream<Uint8List> Function() openStream;
}

abstract interface class UploadFilePicker {
  Future<List<SelectedUploadFile>> pickFiles();
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
