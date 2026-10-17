import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';

abstract interface class AppUpdateRepository {
  Stream<UpdateInstallerEvent> get installerEvents;

  Future<bool> isSupported();

  Future<UpdateCatalog> checkForUpdates();

  Future<bool> canRequestPackageInstalls();

  Future<void> openPackageInstallSettings();

  Future<void> downloadAndInstall(
    UpdateCandidate candidate, {
    required void Function(double progress) onProgress,
  });
}
