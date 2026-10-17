import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';
import 'package:mattermost_flutter/src/features/updates/domain/policies/select_update_catalog.dart';

void main() {
  group('AppVersion', () {
    test('parses release tags and compares semantic and build versions', () {
      expect(
        AppVersion.tryParse('v1.2.3+45'),
        const AppVersion(major: 1, minor: 2, patch: 3, build: 45),
      );
      expect(AppVersion.tryParse('v1.2'), isNull);
      expect(AppVersion.tryParse('v1.2.3-beta'), isNull);

      const InstalledApplication installed = InstalledApplication(
        version: AppVersion(major: 1, minor: 2, patch: 3),
        buildNumber: 45,
        packageName: 'com.example.app',
      );
      expect(
        const AppVersion(
          major: 1,
          minor: 2,
          patch: 3,
          build: 46,
        ).isNewerThan(installed),
        isTrue,
      );
      expect(
        const AppVersion(major: 1, minor: 2, patch: 3).isNewerThan(installed),
        isFalse,
      );
      expect(
        const AppVersion(major: 1, minor: 3, patch: 0).isNewerThan(installed),
        isTrue,
      );
    });
  });

  test('orders every newer release and selects the newest compatible APK', () {
    const InstalledApplication installed = InstalledApplication(
      version: AppVersion(major: 1, minor: 0, patch: 0),
      buildNumber: 10,
      packageName: 'com.example.app',
    );
    final UpdateRelease newestIncompatible = _release(
      const AppVersion(major: 1, minor: 3, patch: 0),
      'x86_64',
    );
    final UpdateRelease newestCompatible = _release(
      const AppVersion(major: 1, minor: 2, patch: 0),
      'arm64-v8a',
    );
    final UpdateRelease oldest = _release(
      const AppVersion(major: 1, minor: 1, patch: 0),
      'armeabi-v7a',
    );

    final UpdateCatalog result = selectUpdateCatalog(
      installed: installed,
      releases: <UpdateRelease>[
        newestIncompatible,
        oldest,
        newestCompatible,
        _release(const AppVersion(major: 0, minor: 9, patch: 0), 'arm64-v8a'),
      ],
      supportedAbis: const <String>['arm64-v8a'],
      isComplete: true,
    );

    expect(
      result.newerReleases.map((UpdateRelease release) => release.version.name),
      <String>['1.1.0', '1.2.0', '1.3.0'],
    );
    expect(result.candidate?.release, same(newestCompatible));
  });

  test('rejects an ambiguous ABI instead of selecting an arbitrary APK', () {
    final UpdateArtifact first = _release(
      const AppVersion(major: 1, minor: 1, patch: 0),
      'arm64-v8a',
    ).artifacts.single;
    final UpdateRelease ambiguous = UpdateRelease(
      version: const AppVersion(major: 1, minor: 1, patch: 0),
      title: 'Ambiguous',
      notes: 'Changes',
      publishedAt: null,
      artifacts: <UpdateArtifact>[
        first,
        UpdateArtifact(
          name: 'another-arm64-v8a.apk',
          downloadUrl: Uri.parse('https://github.com/example/another.apk'),
          size: 20,
          sha256: 'b' * 64,
          abi: 'arm64-v8a',
        ),
      ],
    );

    final UpdateCatalog result = selectUpdateCatalog(
      installed: const InstalledApplication(
        version: AppVersion(major: 1, minor: 0, patch: 0),
        buildNumber: 1,
        packageName: 'com.example.app',
      ),
      releases: <UpdateRelease>[ambiguous],
      supportedAbis: const <String>['arm64-v8a'],
      isComplete: true,
    );

    expect(result.candidate, isNull);
  });
}

UpdateRelease _release(AppVersion version, String abi) => UpdateRelease(
  version: version,
  title: version.displayName,
  notes: 'Changes',
  publishedAt: DateTime.utc(2026),
  artifacts: <UpdateArtifact>[
    UpdateArtifact(
      name: 'mattermost-v${version.displayName}-$abi.apk',
      downloadUrl: Uri.parse('https://github.com/example/$abi.apk'),
      size: 10,
      sha256: 'a' * 64,
      abi: abi,
    ),
  ],
);
