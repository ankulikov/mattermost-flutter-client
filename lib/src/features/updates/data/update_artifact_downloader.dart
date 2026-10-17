import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';

abstract interface class UpdateArtifactDownloader {
  Future<String> download(
    UpdateArtifact artifact, {
    required void Function(double progress) onProgress,
  });

  Future<void> remove(String path);
}
