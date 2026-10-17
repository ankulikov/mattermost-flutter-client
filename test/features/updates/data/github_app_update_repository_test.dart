import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/updates/data/android_package_installer_gateway.dart';
import 'package:mattermost_flutter/src/features/updates/data/github_app_update_repository.dart';
import 'package:mattermost_flutter/src/features/updates/data/github_release_api.dart';
import 'package:mattermost_flutter/src/features/updates/data/installed_application_source.dart';
import 'package:mattermost_flutter/src/features/updates/data/update_artifact_downloader.dart';
import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';

void main() {
  test(
    'paginates, filters prereleases, and maps the matching signed asset',
    () async {
      final _GithubAdapter adapter = _GithubAdapter(<_Response>[
        _Response(
          body: <Object?>[
            _releaseJson(tag: 'v1.2.0', abi: 'arm64-v8a'),
            _releaseJson(tag: 'v9.0.0', abi: 'arm64-v8a', prerelease: true),
          ],
          headers: <String, List<String>>{
            'link': <String>[
              '<https://api.github.com/releases?page=2>; rel="next"',
            ],
            'etag': <String>['page-one'],
          },
        ),
        _Response(
          body: <Object?>[_releaseJson(tag: 'v1.1.0', abi: 'armeabi-v7a')],
        ),
      ]);
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'))
        ..httpClientAdapter = adapter;
      final GithubAppUpdateRepository repository = GithubAppUpdateRepository(
        releaseApi: GithubReleaseApi(dio: dio),
        installedApplicationSource: const _InstalledSource(),
        installerGateway: _InstallerGateway(),
        downloader: _Downloader(),
      );

      final UpdateCatalog catalog = await repository.checkForUpdates();

      expect(adapter.requests, hasLength(2));
      expect(
        catalog.newerReleases.map(
          (UpdateRelease release) => release.version.name,
        ),
        <String>['1.1.0', '1.2.0'],
      );
      expect(catalog.candidate?.release.version.name, '1.2.0');
      expect(catalog.candidate?.artifact.sha256, 'a' * 64);
      expect(catalog.isComplete, isTrue);
    },
  );

  test('marks history partial when a later page fails', () async {
    final _GithubAdapter adapter = _GithubAdapter(<_Response>[
      _Response(
        body: <Object?>[_releaseJson(tag: 'v1.1.0', abi: 'arm64-v8a')],
        headers: <String, List<String>>{
          'link': <String>[
            '<https://api.github.com/releases?page=2>; rel="next"',
          ],
        },
      ),
      const _Response(statusCode: 500, body: <Object?>[]),
    ]);
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'))
      ..httpClientAdapter = adapter;
    final GithubAppUpdateRepository repository = GithubAppUpdateRepository(
      releaseApi: GithubReleaseApi(dio: dio),
      installedApplicationSource: const _InstalledSource(),
      installerGateway: _InstallerGateway(),
      downloader: _Downloader(),
    );

    final UpdateCatalog catalog = await repository.checkForUpdates();

    expect(catalog.newerReleases, hasLength(1));
    expect(catalog.isComplete, isFalse);
  });

  test('marks history partial when a stable release tag is invalid', () async {
    final _GithubAdapter adapter = _GithubAdapter(<_Response>[
      _Response(
        body: <Object?>[
          _releaseJson(tag: 'latest', abi: 'arm64-v8a'),
          _releaseJson(tag: 'v1.1.0', abi: 'arm64-v8a'),
        ],
      ),
    ]);
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'))
      ..httpClientAdapter = adapter;
    final GithubAppUpdateRepository repository = GithubAppUpdateRepository(
      releaseApi: GithubReleaseApi(dio: dio),
      installedApplicationSource: const _InstalledSource(),
      installerGateway: _InstallerGateway(),
      downloader: _Downloader(),
    );

    final UpdateCatalog catalog = await repository.checkForUpdates();

    expect(catalog.newerReleases, hasLength(1));
    expect(catalog.isComplete, isFalse);
  });

  test('reuses an ETag response when GitHub reports not modified', () async {
    final _GithubAdapter adapter = _GithubAdapter(<_Response>[
      _Response(
        body: <Object?>[_releaseJson(tag: 'v1.1.0', abi: 'arm64-v8a')],
        headers: const <String, List<String>>{
          'etag': <String>['release-page'],
        },
      ),
      const _Response(statusCode: 304, body: ''),
    ]);
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'))
      ..httpClientAdapter = adapter;
    final GithubReleaseApi api = GithubReleaseApi(dio: dio);

    final GithubReleaseListing first = await api.listStableReleases();
    final GithubReleaseListing second = await api.listStableReleases();

    expect(first.releases.single.tagName, 'v1.1.0');
    expect(second.releases.single.tagName, 'v1.1.0');
    expect(adapter.requests.last.headers['If-None-Match'], 'release-page');
  });

  test('honors GitHub rate-limit retry headers', () async {
    final DateTime now = DateTime.utc(2026, 10, 17);
    final _GithubAdapter adapter = _GithubAdapter(<_Response>[
      const _Response(
        statusCode: 429,
        body: <String, Object?>{'message': 'rate limited'},
        headers: <String, List<String>>{
          'retry-after': <String>['120'],
        },
      ),
    ]);
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'))
      ..httpClientAdapter = adapter;
    final GithubReleaseApi api = GithubReleaseApi(dio: dio, clock: () => now);

    await expectLater(
      api.listStableReleases(),
      throwsA(
        isA<AppUpdateRateLimitedException>().having(
          (AppUpdateRateLimitedException error) => error.retryAt,
          'retryAt',
          now.add(const Duration(minutes: 2)),
        ),
      ),
    );
    await expectLater(
      api.listStableReleases(),
      throwsA(isA<AppUpdateRateLimitedException>()),
    );
    expect(adapter.requests, hasLength(1));
  });

  test('requires digest, exact ABI, and GitHub HTTPS download host', () async {
    final Map<String, Object?> invalid = _releaseJson(
      tag: 'v1.2.0',
      abi: 'arm64-v8a',
    );
    final Map<String, Object?> asset =
        (invalid['assets']! as List<Object?>).single as Map<String, Object?>;
    asset['digest'] = null;
    asset['browser_download_url'] = 'https://example.com/update.apk';
    final _GithubAdapter adapter = _GithubAdapter(<_Response>[
      _Response(body: <Object?>[invalid]),
    ]);
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'))
      ..httpClientAdapter = adapter;
    final GithubAppUpdateRepository repository = GithubAppUpdateRepository(
      releaseApi: GithubReleaseApi(dio: dio),
      installedApplicationSource: const _InstalledSource(),
      installerGateway: _InstallerGateway(),
      downloader: _Downloader(),
    );

    final UpdateCatalog catalog = await repository.checkForUpdates();

    expect(catalog.newerReleases, hasLength(1));
    expect(catalog.candidate, isNull);
  });

  test(
    'normalizes Flutter split APK offsets for same-version builds',
    () async {
      final _GithubAdapter adapter = _GithubAdapter(<_Response>[
        _Response(
          body: <Object?>[_releaseJson(tag: 'v1.0.0+2', abi: 'arm64-v8a')],
        ),
      ]);
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'))
        ..httpClientAdapter = adapter;
      final GithubAppUpdateRepository repository = GithubAppUpdateRepository(
        releaseApi: GithubReleaseApi(dio: dio),
        installedApplicationSource: const _InstalledSource(buildNumber: 2001),
        installerGateway: _InstallerGateway(versionCodeOffset: 2000),
        downloader: _Downloader(),
      );

      final UpdateCatalog catalog = await repository.checkForUpdates();

      expect(catalog.installed.buildNumber, 1);
      expect(catalog.candidate?.release.version.build, 2);
    },
  );

  test('removes the verified APK after the native gateway stages it', () async {
    final _Downloader downloader = _Downloader();
    final _InstallerGateway installer = _InstallerGateway();
    final GithubAppUpdateRepository repository = GithubAppUpdateRepository(
      releaseApi: GithubReleaseApi(dio: Dio()),
      installedApplicationSource: const _InstalledSource(),
      installerGateway: installer,
      downloader: downloader,
    );
    final UpdateCandidate candidate = UpdateCandidate(
      release: _release(),
      artifact: _artifact(),
    );

    await repository.downloadAndInstall(candidate, onProgress: (_) {});

    expect(installer.installedPath, '/temporary/update.apk');
    expect(downloader.removedPath, '/temporary/update.apk');
  });
}

Map<String, Object?> _releaseJson({
  required String tag,
  required String abi,
  bool prerelease = false,
}) => <String, Object?>{
  'tag_name': tag,
  'name': 'Mattermost $tag',
  'body': 'Release notes',
  'draft': false,
  'prerelease': prerelease,
  'published_at': '2026-10-17T00:00:00Z',
  'assets': <Object?>[
    <String, Object?>{
      'name': 'mattermost-$tag-$abi.apk',
      'browser_download_url':
          'https://github.com/ankulikov/mattermost-flutter-client/releases/download/$tag/update-$abi.apk',
      'size': 2048,
      'digest': 'sha256:${'a' * 64}',
    },
  ],
};

UpdateArtifact _artifact() => UpdateArtifact(
  name: 'update.apk',
  downloadUrl: Uri.parse('https://github.com/example/update.apk'),
  size: 10,
  sha256: 'a' * 64,
  abi: 'arm64-v8a',
);

UpdateRelease _release() => UpdateRelease(
  version: const AppVersion(major: 1, minor: 1, patch: 0),
  title: 'One',
  notes: 'Notes',
  publishedAt: null,
  artifacts: <UpdateArtifact>[_artifact()],
);

final class _InstalledSource implements InstalledApplicationSource {
  const _InstalledSource({this.buildNumber = 1});

  final int buildNumber;

  @override
  Future<InstalledApplication> load() async => InstalledApplication(
    version: const AppVersion(major: 1, minor: 0, patch: 0),
    buildNumber: buildNumber,
    packageName: 'com.mattermost.mattermost_flutter',
  );
}

final class _InstallerGateway implements PackageInstallerGateway {
  _InstallerGateway({int versionCodeOffset = 0})
    : _configuredVersionCodeOffset = versionCodeOffset;

  final int _configuredVersionCodeOffset;
  String? installedPath;

  @override
  Stream<UpdateInstallerEvent> get events =>
      const Stream<UpdateInstallerEvent>.empty();

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<List<String>> supportedAbis() async => const <String>['arm64-v8a'];

  @override
  Future<int> versionCodeOffset() async => _configuredVersionCodeOffset;

  @override
  Future<bool> canRequestPackageInstalls() async => true;

  @override
  Future<void> openPackageInstallSettings() async {}

  @override
  Future<void> install({
    required String apkPath,
    required String expectedPackageName,
  }) async {
    installedPath = apkPath;
  }
}

final class _Downloader implements UpdateArtifactDownloader {
  String? removedPath;

  @override
  Future<String> download(
    UpdateArtifact artifact, {
    required void Function(double progress) onProgress,
  }) async => '/temporary/update.apk';

  @override
  Future<void> remove(String path) async => removedPath = path;
}

final class _Response {
  const _Response({this.statusCode = 200, required this.body, this.headers});

  final int statusCode;
  final Object body;
  final Map<String, List<String>>? headers;
}

final class _GithubAdapter implements HttpClientAdapter {
  _GithubAdapter(this.responses);

  final List<_Response> responses;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final _Response response = responses[requests.length - 1];
    return ResponseBody.fromString(
      response.body is String
          ? response.body as String
          : jsonEncode(response.body),
      response.statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
        ...?response.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
