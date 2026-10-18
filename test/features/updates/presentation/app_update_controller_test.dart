import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/models/user_preferences.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/repositories/user_preferences_repository.dart';
import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';
import 'package:mattermost_flutter/src/features/updates/domain/repositories/app_update_repository.dart';
import 'package:mattermost_flutter/src/features/updates/presentation/app_update_controller.dart';

void main() {
  test('initial failure is retryable', () async {
    final _UpdateRepository repository = _UpdateRepository()
      ..checkError = StateError('offline');
    final _ControllerHarness harness = _ControllerHarness(repository);
    addTearDown(harness.dispose);

    await harness.controller.check();
    expect(harness.state.catalog, isNull);
    expect(harness.state.checkStatus, isA<OperationFailed>());

    repository
      ..checkError = null
      ..catalog = _catalog();
    await harness.controller.check(replaceCurrent: true);
    expect(harness.state.catalog, same(repository.catalog));
    expect(harness.state.checkStatus, isA<OperationIdle>());
  });

  test('refresh failure preserves the useful catalog', () async {
    final _UpdateRepository repository = _UpdateRepository()
      ..catalog = _catalog();
    final _ControllerHarness harness = _ControllerHarness(repository);
    addTearDown(harness.dispose);
    await harness.controller.check();
    final UpdateCatalog loaded = harness.state.catalog!;

    repository.checkError = StateError('offline');
    await harness.controller.check(replaceCurrent: true);

    expect(harness.state.catalog, same(loaded));
    expect(harness.state.checkStatus, isA<OperationFailed>());
  });

  test('permission, progress, and installer events remain distinct', () async {
    final _UpdateRepository repository = _UpdateRepository()
      ..catalog = _catalog()
      ..canInstall = false;
    final _ControllerHarness harness = _ControllerHarness(repository);
    addTearDown(harness.dispose);
    await harness.controller.check();

    await harness.controller.install();
    expect(harness.state.installPhase, isA<UpdateInstallPermissionRequired>());

    repository.canInstall = true;
    await harness.controller.handleResumed();
    expect(harness.state.installPhase, isA<UpdateInstallIdle>());

    await harness.controller.install();
    expect(repository.progressValues, <double>[0.25, 1]);
    expect(harness.state.installPhase, isA<UpdateInstallWaitingForSystem>());

    repository.events.add(const UpdateInstallerAwaitingUserAction());
    await Future<void>.delayed(Duration.zero);
    expect(
      (harness.state.installPhase as UpdateInstallWaitingForSystem)
          .needsConfirmation,
      isTrue,
    );

    repository.events.add(const UpdateInstallerFailed('blocked'));
    await Future<void>.delayed(Duration.zero);
    expect(harness.state.installPhase, isA<UpdateInstallFailure>());
  });

  test(
    'automatic checks are bounded by the persisted one day interval',
    () async {
      var now = DateTime.utc(2026, 10, 17);
      final _UpdateRepository repository = _UpdateRepository()
        ..catalog = _catalog();
      final _PreferencesRepository preferences = _PreferencesRepository();
      final Provider<AppUpdateRepository> repositoryProvider =
          Provider<AppUpdateRepository>((Ref ref) => repository);
      final Provider<UserPreferencesRepository> preferencesProvider =
          Provider<UserPreferencesRepository>((Ref ref) => preferences);
      late final NotifierProvider<AppUpdateController, AppUpdateViewState>
      controllerProvider;
      controllerProvider =
          NotifierProvider<AppUpdateController, AppUpdateViewState>(
            () => AppUpdateController(
              repositoryProvider,
              preferencesProvider,
              clock: () => now,
            ),
          );
      final ProviderContainer container = ProviderContainer();
      addTearDown(() {
        container.dispose();
        unawaited(repository.dispose());
      });
      container.listen(controllerProvider, (_, _) {});

      await container.read(controllerProvider.notifier).checkIfDue();
      await container.read(controllerProvider.notifier).checkIfDue();
      expect(repository.checkCalls, 1);
      expect(preferences.lastUpdateCheck, now);

      now = now.add(const Duration(hours: 23, minutes: 59));
      await container.read(controllerProvider.notifier).checkIfDue();
      expect(repository.checkCalls, 1);

      now = now.add(const Duration(minutes: 1));
      await container.read(controllerProvider.notifier).checkIfDue();
      expect(repository.checkCalls, 2);
    },
  );

  test('manual checks and Later both record the current time', () async {
    var now = DateTime.utc(2026, 10, 17, 8);
    final _UpdateRepository repository = _UpdateRepository()
      ..catalog = _catalog();
    final _PreferencesRepository preferences = _PreferencesRepository(
      lastUpdateCheck: now,
    );
    final _ControllerHarness harness = _ControllerHarness(
      repository,
      preferences: preferences,
      clock: () => now,
    );
    addTearDown(harness.dispose);

    now = now.add(const Duration(hours: 2));
    await harness.controller.check(replaceCurrent: true);
    expect(repository.checkCalls, 1);
    expect(preferences.lastUpdateCheck, now);

    now = now.add(const Duration(hours: 3));
    await harness.controller.postponeAutomaticChecks();
    expect(preferences.lastUpdateCheck, now);
  });

  test('a preference read failure does not start an automatic check', () async {
    final _UpdateRepository repository = _UpdateRepository()
      ..catalog = _catalog();
    final _ControllerHarness harness = _ControllerHarness(
      repository,
      preferences: _PreferencesRepository(
        readError: StateError('database unavailable'),
      ),
    );
    addTearDown(harness.dispose);

    await harness.controller.checkIfDue();

    expect(repository.checkCalls, 0);
    expect(harness.state.checkStatus, isA<OperationFailed>());
  });
}

final class _ControllerHarness {
  _ControllerHarness(
    this.repository, {
    _PreferencesRepository? preferences,
    DateTime Function()? clock,
  }) : preferences = preferences ?? _PreferencesRepository() {
    repositoryProvider = Provider<AppUpdateRepository>((Ref ref) => repository);
    preferencesProvider = Provider<UserPreferencesRepository>(
      (Ref ref) => this.preferences,
    );
    controllerProvider =
        NotifierProvider<AppUpdateController, AppUpdateViewState>(
          () => AppUpdateController(
            repositoryProvider,
            preferencesProvider,
            clock: clock,
          ),
        );
    container = ProviderContainer()..listen(controllerProvider, (_, _) {});
  }

  final _UpdateRepository repository;
  final _PreferencesRepository preferences;
  late final Provider<AppUpdateRepository> repositoryProvider;
  late final Provider<UserPreferencesRepository> preferencesProvider;
  late final NotifierProvider<AppUpdateController, AppUpdateViewState>
  controllerProvider;
  late final ProviderContainer container;

  AppUpdateController get controller =>
      container.read(controllerProvider.notifier);
  AppUpdateViewState get state => container.read(controllerProvider);

  void dispose() {
    container.dispose();
    unawaited(repository.dispose());
  }
}

final class _PreferencesRepository implements UserPreferencesRepository {
  _PreferencesRepository({this.lastUpdateCheck, this.readError});

  DateTime? lastUpdateCheck;
  final Object? readError;

  @override
  Future<UserPreferences> read() async => UserPreferences.defaults;

  @override
  Future<DateTime?> readLastUpdateCheck() async {
    if (readError case final Object error) throw error;
    return lastUpdateCheck;
  }

  @override
  Future<void> update(UserPreferences preferences) async {}

  @override
  Future<void> writeLastUpdateCheck(DateTime checkedAt) async {
    lastUpdateCheck = checkedAt;
  }
}

final class _UpdateRepository implements AppUpdateRepository {
  final StreamController<UpdateInstallerEvent> events =
      StreamController<UpdateInstallerEvent>.broadcast();
  UpdateCatalog? catalog;
  Object? checkError;
  bool canInstall = true;
  int checkCalls = 0;
  final List<double> progressValues = <double>[];

  Future<void> dispose() => events.close();

  @override
  Stream<UpdateInstallerEvent> get installerEvents => events.stream;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<UpdateCatalog> checkForUpdates() async {
    checkCalls += 1;
    if (checkError case final Object error) throw error;
    return catalog!;
  }

  @override
  Future<bool> canRequestPackageInstalls() async => canInstall;

  @override
  Future<void> openPackageInstallSettings() async {}

  @override
  Future<void> downloadAndInstall(
    UpdateCandidate candidate, {
    required void Function(double progress) onProgress,
  }) async {
    for (final double progress in <double>[0.25, 1]) {
      progressValues.add(progress);
      onProgress(progress);
    }
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
