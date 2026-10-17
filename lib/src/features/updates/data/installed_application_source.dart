import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

abstract interface class InstalledApplicationSource {
  Future<InstalledApplication> load();
}

final class PackageInfoInstalledApplicationSource
    implements InstalledApplicationSource {
  const PackageInfoInstalledApplicationSource();

  @override
  Future<InstalledApplication> load() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    final AppVersion? version = AppVersion.tryParse(info.version);
    final int? buildNumber = int.tryParse(info.buildNumber);
    if (version == null || buildNumber == null) {
      throw const AppUpdateInvalidReleaseException(
        'The installed application version is invalid.',
      );
    }
    return InstalledApplication(
      version: version,
      buildNumber: buildNumber,
      packageName: info.packageName,
    );
  }
}
