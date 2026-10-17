/// A semantic application version plus its optional release build number.
final class AppVersion implements Comparable<AppVersion> {
  const AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.build,
  });

  final int major;
  final int minor;
  final int patch;
  final int? build;

  static AppVersion? tryParse(String value) {
    final RegExpMatch? match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    return AppVersion(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
      build: match.group(4) == null ? null : int.parse(match.group(4)!),
    );
  }

  String get name => '$major.$minor.$patch';

  String get displayName => build == null ? name : '$name+$build';

  bool isNewerThan(InstalledApplication installed) {
    final int semanticComparison = compareSemantic(installed.version);
    if (semanticComparison != 0) return semanticComparison > 0;
    return build != null && build! > installed.buildNumber;
  }

  int compareSemantic(AppVersion other) {
    for (final (int current, int candidate) in <(int, int)>[
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final int comparison = current.compareTo(candidate);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  @override
  int compareTo(AppVersion other) {
    final int semanticComparison = compareSemantic(other);
    if (semanticComparison != 0) return semanticComparison;
    return (build ?? -1).compareTo(other.build ?? -1);
  }

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch &&
      build == other.build;

  @override
  int get hashCode => Object.hash(major, minor, patch, build);
}

final class InstalledApplication {
  const InstalledApplication({
    required this.version,
    required this.buildNumber,
    required this.packageName,
  });

  final AppVersion version;
  final int buildNumber;
  final String packageName;

  String get displayVersion => '${version.name}+$buildNumber';
}

final class UpdateArtifact {
  const UpdateArtifact({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.sha256,
    required this.abi,
  });

  final String name;
  final Uri downloadUrl;
  final int size;
  final String sha256;
  final String abi;
}

final class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.title,
    required this.notes,
    required this.publishedAt,
    required this.artifacts,
  });

  final AppVersion version;
  final String title;
  final String notes;
  final DateTime? publishedAt;
  final List<UpdateArtifact> artifacts;

  UpdateArtifact? compatibleArtifact(List<String> supportedAbis) {
    for (final String abi in supportedAbis) {
      final List<UpdateArtifact> matching = artifacts
          .where((UpdateArtifact artifact) => artifact.abi == abi)
          .toList(growable: false);
      if (matching.length > 1) return null;
      if (matching.length == 1) return matching.single;
    }
    return null;
  }
}

final class UpdateCandidate {
  const UpdateCandidate({required this.release, required this.artifact});

  final UpdateRelease release;
  final UpdateArtifact artifact;
}

final class UpdateCatalog {
  const UpdateCatalog({
    required this.installed,
    required this.newerReleases,
    required this.isComplete,
    this.candidate,
  });

  final InstalledApplication installed;
  final List<UpdateRelease> newerReleases;
  final UpdateCandidate? candidate;
  final bool isComplete;

  bool get hasUpdates => newerReleases.isNotEmpty;
}

sealed class UpdateInstallerEvent {
  const UpdateInstallerEvent();
}

final class UpdateInstallerAwaitingUserAction extends UpdateInstallerEvent {
  const UpdateInstallerAwaitingUserAction();
}

final class UpdateInstallerInstalling extends UpdateInstallerEvent {
  const UpdateInstallerInstalling();
}

final class UpdateInstallerSucceeded extends UpdateInstallerEvent {
  const UpdateInstallerSucceeded();
}

final class UpdateInstallerCancelled extends UpdateInstallerEvent {
  const UpdateInstallerCancelled();
}

final class UpdateInstallerFailed extends UpdateInstallerEvent {
  const UpdateInstallerFailed(this.reason, {this.rawError});

  final String reason;
  final String? rawError;
}

sealed class AppUpdateException implements Exception {
  const AppUpdateException();
}

final class AppUpdateUnsupportedException extends AppUpdateException {
  const AppUpdateUnsupportedException();
}

final class AppUpdatePermissionRequiredException extends AppUpdateException {
  const AppUpdatePermissionRequiredException();
}

final class AppUpdateRateLimitedException extends AppUpdateException {
  const AppUpdateRateLimitedException(this.retryAt);

  final DateTime? retryAt;
}

final class AppUpdateInvalidReleaseException extends AppUpdateException {
  const AppUpdateInvalidReleaseException(this.reason);

  final String reason;
}

final class AppUpdateDownloadException extends AppUpdateException {
  const AppUpdateDownloadException(this.reason);

  final String reason;
}

final class AppUpdateInstallException extends AppUpdateException {
  const AppUpdateInstallException(this.reason, {this.rawError});

  final String reason;
  final String? rawError;
}
