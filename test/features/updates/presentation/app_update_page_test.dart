import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/providers/repository_providers.dart';
import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';
import 'package:mattermost_flutter/src/features/updates/domain/repositories/app_update_repository.dart';
import 'package:mattermost_flutter/src/features/updates/presentation/app_update_page.dart';

void main() {
  Future<void> pumpPage(
    WidgetTester tester,
    _UpdateRepository repository, {
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appUpdateRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: const AppUpdatePage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders compact release history at large text scale', (
    WidgetTester tester,
  ) async {
    final _UpdateRepository repository = _UpdateRepository(catalog: _catalog());
    await pumpPage(tester, repository, textScale: 2);

    expect(
      find.byKey(const ValueKey<String>('app-update-compact')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Mattermost 1.1.0'),
      300,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Mattermost 1.1.0'), findsOneWidget);
    expect(find.text('New messages experience'), findsOneWidget);
    expect(find.text('Install 1.1.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the expanded layout on the wide side of the breakpoint', (
    WidgetTester tester,
  ) async {
    await pumpPage(
      tester,
      _UpdateRepository(catalog: _catalog()),
      size: const Size(700, 900),
      textScale: 1.5,
    );

    expect(
      find.byKey(const ValueKey<String>('app-update-expanded')),
      findsOneWidget,
    );
    expect(find.text('Installed version'), findsOneWidget);
    expect(find.text('Available version'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows retry after initial failure', (WidgetTester tester) async {
    final _UpdateRepository repository = _UpdateRepository(
      checkError: StateError('offline'),
    );
    await pumpPage(tester, repository);

    expect(find.text('Could not check for updates.'), findsOneWidget);
    repository
      ..checkError = null
      ..catalog = _catalog();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Mattermost 1.1.0'), findsOneWidget);
  });

  testWidgets('keeps releases visible when refresh fails', (
    WidgetTester tester,
  ) async {
    final _UpdateRepository repository = _UpdateRepository(catalog: _catalog());
    await pumpPage(tester, repository);
    repository.checkError = StateError('offline');

    await tester.tap(find.byKey(const ValueKey<String>('app-update-check')));
    await tester.pumpAndSettle();

    expect(find.text('Mattermost 1.1.0'), findsOneWidget);
    expect(find.text('Could not check for updates.'), findsOneWidget);
  });

  testWidgets('requests install permission and resumes installation', (
    WidgetTester tester,
  ) async {
    final _UpdateRepository repository = _UpdateRepository(
      catalog: _catalog(),
      canInstall: false,
    );
    await pumpPage(tester, repository);

    await tester.tap(find.byKey(const ValueKey<String>('app-update-install')));
    await tester.pumpAndSettle();
    expect(find.text('Allow app installations'), findsOneWidget);

    await tester.tap(find.text('Open Android settings'));
    await tester.pump();
    expect(repository.settingsCalls, 1);

    repository.canInstall = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('app-update-install')));
    await tester.pumpAndSettle();

    expect(repository.installCalls, 1);
    expect(find.text('Android is installing the update.'), findsOneWidget);
  });

  testWidgets('blocks installation while release history is partial', (
    WidgetTester tester,
  ) async {
    await pumpPage(
      tester,
      _UpdateRepository(catalog: _catalog(complete: false)),
    );

    expect(
      find.byKey(const ValueKey<String>('app-update-partial-history')),
      findsOneWidget,
    );
    final FilledButton install = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('app-update-install')),
    );
    expect(install.onPressed, isNull);
  });

  testWidgets('shows raw installer error below the friendly failure', (
    WidgetTester tester,
  ) async {
    final _UpdateRepository repository = _UpdateRepository(
      catalog: _catalog(),
      installError: const AppUpdateInstallException(
        'install_failed',
        rawError: 'code=install_failed; message=Package is invalid.',
      ),
    );
    await pumpPage(tester, repository);

    await tester.tap(find.byKey(const ValueKey<String>('app-update-install')));
    await tester.pumpAndSettle();

    expect(find.text('Could not install the update.'), findsOneWidget);
    expect(
      find.text('code=install_failed; message=Package is invalid.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('app-update-error-details')),
      findsOneWidget,
    );
  });
}

final class _UpdateRepository implements AppUpdateRepository {
  _UpdateRepository({
    this.catalog,
    this.checkError,
    this.installError,
    this.canInstall = true,
  });

  UpdateCatalog? catalog;
  Object? checkError;
  Object? installError;
  bool canInstall;
  int settingsCalls = 0;
  int installCalls = 0;

  @override
  Stream<UpdateInstallerEvent> get installerEvents =>
      const Stream<UpdateInstallerEvent>.empty();

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<UpdateCatalog> checkForUpdates() async {
    if (checkError case final Object error) throw error;
    return catalog!;
  }

  @override
  Future<bool> canRequestPackageInstalls() async => canInstall;

  @override
  Future<void> openPackageInstallSettings() async => settingsCalls += 1;

  @override
  Future<void> downloadAndInstall(
    UpdateCandidate candidate, {
    required void Function(double progress) onProgress,
  }) async {
    installCalls += 1;
    if (installError case final Object error) throw error;
    onProgress(0.5);
    onProgress(1);
  }
}

UpdateCatalog _catalog({bool complete = true}) {
  final UpdateArtifact artifact = UpdateArtifact(
    name: 'mattermost-v1.1.0-arm64-v8a.apk',
    downloadUrl: Uri.parse('https://github.com/example/update.apk'),
    size: 10,
    sha256: 'a' * 64,
    abi: 'arm64-v8a',
  );
  final UpdateRelease release = UpdateRelease(
    version: const AppVersion(major: 1, minor: 1, patch: 0),
    title: 'Mattermost 1.1.0',
    notes: 'New messages experience',
    publishedAt: DateTime.utc(2026, 10, 17),
    artifacts: <UpdateArtifact>[artifact],
  );
  return UpdateCatalog(
    installed: const InstalledApplication(
      version: AppVersion(major: 1, minor: 0, patch: 0),
      buildNumber: 10,
      packageName: 'com.mattermost.mattermost_flutter',
    ),
    newerReleases: <UpdateRelease>[release],
    candidate: UpdateCandidate(release: release, artifact: artifact),
    isComplete: complete,
  );
}
