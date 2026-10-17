import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
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

  test('automatic checks are bounded by the six hour interval', () async {
    var now = DateTime.utc(2026, 10, 17);
    final _UpdateRepository repository = _UpdateRepository()
      ..catalog = _catalog();
    final Provider<AppUpdateRepository> repositoryProvider =
        Provider<AppUpdateRepository>((Ref ref) => repository);
    late final NotifierProvider<AppUpdateController, AppUpdateViewState>
    controllerProvider;
    controllerProvider =
        NotifierProvider<AppUpdateController, AppUpdateViewState>(
          () => AppUpdateController(repositoryProvider, clock: () => now),
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

    now = now.add(const Duration(hours: 6));
    await container.read(controllerProvider.notifier).checkIfDue();
    expect(repository.checkCalls, 2);
  });
}

final class _ControllerHarness {
  _ControllerHarness(this.repository) {
    repositoryProvider = Provider<AppUpdateRepository>((Ref ref) => repository);
    controllerProvider =
        NotifierProvider<AppUpdateController, AppUpdateViewState>(
          () => AppUpdateController(repositoryProvider),
        );
    container = ProviderContainer()..listen(controllerProvider, (_, _) {});
  }

  final _UpdateRepository repository;
  late final Provider<AppUpdateRepository> repositoryProvider;
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
