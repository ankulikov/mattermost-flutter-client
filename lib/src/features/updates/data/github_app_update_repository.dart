import 'package:mattermost_flutter/src/features/updates/data/android_package_installer_gateway.dart';
import 'package:mattermost_flutter/src/features/updates/data/github_release_api.dart';
import 'package:mattermost_flutter/src/features/updates/data/installed_application_source.dart';
import 'package:mattermost_flutter/src/features/updates/data/update_artifact_downloader.dart';
import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';
import 'package:mattermost_flutter/src/features/updates/domain/policies/select_update_catalog.dart';
import 'package:mattermost_flutter/src/features/updates/domain/repositories/app_update_repository.dart';

final class GithubAppUpdateRepository implements AppUpdateRepository {
  GithubAppUpdateRepository({
    required GithubReleaseApi releaseApi,
    required InstalledApplicationSource installedApplicationSource,
    required PackageInstallerGateway installerGateway,
    required UpdateArtifactDownloader downloader,
  }) : _releaseApi = releaseApi,
       _installedApplicationSource = installedApplicationSource,
       _installerGateway = installerGateway,
       _downloader = downloader;

  static const Set<String> _knownAndroidAbis = <String>{
    'arm64-v8a',
    'armeabi-v7a',
    'x86_64',
  };

  final GithubReleaseApi _releaseApi;
  final InstalledApplicationSource _installedApplicationSource;
  final PackageInstallerGateway _installerGateway;
  final UpdateArtifactDownloader _downloader;

  @override
  Stream<UpdateInstallerEvent> get installerEvents => _installerGateway.events;

  @override
  Future<bool> isSupported() => _installerGateway.isSupported();

  @override
  Future<UpdateCatalog> checkForUpdates() async {
    if (!await isSupported()) throw const AppUpdateUnsupportedException();
    final (
      InstalledApplication rawInstalled,
      List<String> supportedAbis,
      int versionCodeOffset,
    ) = await (
      _installedApplicationSource.load(),
      _installerGateway.supportedAbis(),
      _installerGateway.versionCodeOffset(),
    ).wait;
    final InstalledApplication installed = InstalledApplication(
      version: rawInstalled.version,
      buildNumber: rawInstalled.buildNumber >= versionCodeOffset
          ? rawInstalled.buildNumber - versionCodeOffset
          : rawInstalled.buildNumber,
      packageName: rawInstalled.packageName,
    );
    final GithubReleaseListing listing = await _releaseApi.listStableReleases();
    final List<UpdateRelease> releases = <UpdateRelease>[];
    var allStableTagsValid = true;
    for (final GithubReleaseDto dto in listing.releases) {
      final UpdateRelease? release = _mapRelease(dto);
      if (release == null) {
        allStableTagsValid = false;
      } else {
        releases.add(release);
      }
    }
    return selectUpdateCatalog(
      installed: installed,
      releases: releases,
      supportedAbis: supportedAbis,
      isComplete: listing.isComplete && allStableTagsValid,
    );
  }

  @override
  Future<bool> canRequestPackageInstalls() =>
      _installerGateway.canRequestPackageInstalls();

  @override
  Future<void> openPackageInstallSettings() =>
      _installerGateway.openPackageInstallSettings();

  @override
  Future<void> downloadAndInstall(
    UpdateCandidate candidate, {
    required void Function(double progress) onProgress,
  }) async {
    if (!await canRequestPackageInstalls()) {
      throw const AppUpdatePermissionRequiredException();
    }
    final InstalledApplication installed = await _installedApplicationSource
        .load();
    final String path = await _downloader.download(
      candidate.artifact,
      onProgress: onProgress,
    );
    try {
      await _installerGateway.install(
        apkPath: path,
        expectedPackageName: installed.packageName,
      );
    } finally {
      await _downloader.remove(path);
    }
  }

  UpdateRelease? _mapRelease(GithubReleaseDto dto) {
    final AppVersion? version = AppVersion.tryParse(dto.tagName);
    if (version == null) return null;
    final List<UpdateArtifact> artifacts = dto.assets
        .map(_mapArtifact)
        .nonNulls
        .toList(growable: false);
    final String title = dto.name.trim();
    return UpdateRelease(
      version: version,
      title: title.isEmpty ? version.displayName : title,
      notes: dto.body.trim(),
      publishedAt: dto.publishedAt,
      artifacts: List<UpdateArtifact>.unmodifiable(artifacts),
    );
  }

  UpdateArtifact? _mapArtifact(GithubReleaseAssetDto dto) {
    final Uri? downloadUrl = dto.downloadUrl;
    final String? digest = dto.digest;
    if (downloadUrl == null ||
        downloadUrl.scheme != 'https' ||
        downloadUrl.host != 'github.com' ||
        dto.size <= 0 ||
        digest == null) {
      return null;
    }
    final RegExpMatch? match = RegExp(
      r'-(arm64-v8a|armeabi-v7a|x86_64)\.apk$',
    ).firstMatch(dto.name);
    final String? abi = match?.group(1);
    if (abi == null || !_knownAndroidAbis.contains(abi)) return null;
    final RegExpMatch? digestMatch = RegExp(
      r'^sha256:([0-9a-fA-F]{64})$',
    ).firstMatch(digest);
    if (digestMatch == null) return null;
    return UpdateArtifact(
      name: dto.name,
      downloadUrl: downloadUrl,
      size: dto.size,
      sha256: digestMatch.group(1)!,
      abi: abi,
    );
  }
}
