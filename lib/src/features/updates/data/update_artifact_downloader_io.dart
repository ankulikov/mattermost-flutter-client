import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/features/updates/data/update_artifact_downloader.dart';
import 'package:mattermost_flutter/src/features/updates/data/verified_update_artifact.dart';
import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

UpdateArtifactDownloader createUpdateArtifactDownloader(Dio dio) =>
    IoUpdateArtifactDownloader(dio: dio);

final class IoUpdateArtifactDownloader implements UpdateArtifactDownloader {
  IoUpdateArtifactDownloader({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<String> download(
    UpdateArtifact artifact, {
    required void Function(double progress) onProgress,
  }) async {
    final String safeName = p.basename(artifact.name);
    if (safeName != artifact.name || !safeName.endsWith('.apk')) {
      throw const AppUpdateDownloadException('invalid_asset_name');
    }
    final Directory temporary = await getTemporaryDirectory();
    final Directory updateDirectory = Directory(
      p.join(temporary.path, 'mattermost-updates'),
    );
    await updateDirectory.create(recursive: true);
    final File partial = File(p.join(updateDirectory.path, '$safeName.part'));
    final File completed = File(p.join(updateDirectory.path, safeName));
    await _deleteIfPresent(partial);
    await _deleteIfPresent(completed);

    final CancelToken cancelToken = CancelToken();
    final RequestCancellation? cancellation = RequestCancellation.current;
    final void Function()? detach = cancellation?.addListener(
      (Object? reason) => cancelToken.cancel(reason),
    );
    try {
      await _dio.download(
        artifact.downloadUrl.toString(),
        partial.path,
        cancelToken: cancelToken,
        deleteOnError: true,
        onReceiveProgress: (int received, int total) {
          final int expected = total > 0 ? total : artifact.size;
          if (expected > 0) {
            onProgress((received / expected).clamp(0, 1));
          }
        },
      );
      await verifyUpdateArtifactFile(partial.path, artifact);
      if (cancellation?.isCancelled ?? false) {
        throw RequestCancelledException(cancellation?.reason);
      }
      final File result = await partial.rename(completed.path);
      onProgress(1);
      return result.path;
    } on DioException catch (error) {
      await _deleteIfPresent(partial);
      if (CancelToken.isCancel(error)) {
        throw RequestCancelledException(error.error);
      }
      throw const AppUpdateDownloadException('network');
    } on Object {
      await _deleteIfPresent(partial);
      rethrow;
    } finally {
      detach?.call();
    }
  }

  Future<void> _deleteIfPresent(File file) async {
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> remove(String path) async {
    final Directory temporary = await getTemporaryDirectory();
    final Directory updateDirectory = Directory(
      p.join(temporary.path, 'mattermost-updates'),
    );
    final File file = File(path);
    final String canonicalDirectory = updateDirectory.absolute.path;
    final String absolutePath = file.absolute.path;
    if (p.isWithin(canonicalDirectory, absolutePath)) {
      await _deleteIfPresent(file);
    }
  }
}
