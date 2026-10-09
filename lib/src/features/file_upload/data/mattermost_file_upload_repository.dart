import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/file_upload/domain/file_upload.dart';

final class MattermostFileUploadRepository implements FileUploadRepository {
  const MattermostFileUploadRepository(this._api);

  final MattermostApi _api;

  @override
  Future<String> upload({
    required String channelId,
    required SelectedUploadFile file,
    required RequestCancellation cancellation,
    required void Function(int sent, int total) onProgress,
  }) async {
    if (file.size < 0) {
      throw const UploadException(UploadFailure.invalidFile);
    }
    try {
      return await cancellation.run(
        () => _api.uploadFile(
          channelId: channelId,
          name: file.name,
          length: file.size,
          stream: file.openStream(),
          onProgress: onProgress,
        ),
      );
    } on DioException catch (error) {
      final int? status = error.response?.statusCode;
      final UploadFailure failure = switch (status) {
        413 => UploadFailure.tooLarge,
        401 => UploadFailure.unauthorized,
        403 => UploadFailure.forbidden,
        429 => UploadFailure.rateLimited,
        _ => UploadFailure.unavailable,
      };
      final String? header = error.response?.headers.value('retry-after');
      throw UploadException(failure, retryAfter: _retryAfter(header));
    } on FormatException {
      throw const UploadException(UploadFailure.unavailable);
    }
  }

  static Duration? _retryAfter(String? header) {
    if (header == null) return null;
    final int? seconds = int.tryParse(header.trim());
    if (seconds != null) return Duration(seconds: seconds < 0 ? 0 : seconds);
    try {
      final DateTime when = DateFormat(
        "EEE, dd MMM yyyy HH:mm:ss 'GMT'",
        'en_US',
      ).parseUtc(header);
      final Duration remaining = when.difference(DateTime.now().toUtc());
      return remaining.isNegative ? Duration.zero : remaining;
    } on FormatException {
      return null;
    }
  }
}
