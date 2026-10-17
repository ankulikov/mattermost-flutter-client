import 'package:dio/dio.dart';
import 'package:mattermost_flutter/src/features/updates/data/update_artifact_downloader.dart';
import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';

UpdateArtifactDownloader createUpdateArtifactDownloader(Dio dio) =>
    const UnsupportedUpdateArtifactDownloader();

final class UnsupportedUpdateArtifactDownloader
    implements UpdateArtifactDownloader {
  const UnsupportedUpdateArtifactDownloader();

  @override
  Future<String> download(
    UpdateArtifact artifact, {
    required void Function(double progress) onProgress,
  }) => Future<String>.error(const AppUpdateUnsupportedException());

  @override
  Future<void> remove(String path) async {}
}
