import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';
import 'package:mattermost_flutter/src/features/updates/domain/repositories/app_update_repository.dart';

sealed class UpdateInstallPhase {
  const UpdateInstallPhase();
}

final class UpdateInstallIdle extends UpdateInstallPhase {
  const UpdateInstallIdle();
}

final class UpdateInstallPermissionRequired extends UpdateInstallPhase {
  const UpdateInstallPermissionRequired();
}

final class UpdateInstallDownloading extends UpdateInstallPhase {
  const UpdateInstallDownloading(this.progress);

  final double progress;
}

final class UpdateInstallWaitingForSystem extends UpdateInstallPhase {
  const UpdateInstallWaitingForSystem({required this.needsConfirmation});

  final bool needsConfirmation;
}

final class UpdateInstallComplete extends UpdateInstallPhase {
  const UpdateInstallComplete();
}

final class UpdateInstallFailure extends UpdateInstallPhase {
  const UpdateInstallFailure(this.error);

  final Object error;
}

final class AppUpdateViewState {
  const AppUpdateViewState({
    this.supported,
    this.catalog,
    this.checkStatus = const OperationStatus.idle(),
    this.installPhase = const UpdateInstallIdle(),
  });

  final bool? supported;
  final UpdateCatalog? catalog;
  final OperationStatus checkStatus;
  final UpdateInstallPhase installPhase;

  AppUpdateViewState copyWith({
    bool? supported,
    UpdateCatalog? catalog,
    OperationStatus? checkStatus,
    UpdateInstallPhase? installPhase,
  }) => AppUpdateViewState(
    supported: supported ?? this.supported,
    catalog: catalog ?? this.catalog,
    checkStatus: checkStatus ?? this.checkStatus,
    installPhase: installPhase ?? this.installPhase,
  );
}

final class AppUpdateController extends Notifier<AppUpdateViewState> {
  AppUpdateController(this._repositoryProvider, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const Duration automaticCheckInterval = Duration(hours: 6);

  final Provider<AppUpdateRepository> _repositoryProvider;
  final DateTime Function() _clock;
  StreamSubscription<UpdateInstallerEvent>? _installerSubscription;
  RequestCancellation? _cancellation;
  DateTime? _lastCheckAttempt;
  int _generation = 0;

  AppUpdateRepository get _repository => ref.read(_repositoryProvider);

  @override
  AppUpdateViewState build() {
    final AppUpdateRepository repository = ref.watch(_repositoryProvider);
    unawaited(_installerSubscription?.cancel());
    _installerSubscription = repository.installerEvents.listen(
      _handleInstallerEvent,
    );
    ref.onDispose(() {
      _cancellation?.cancel();
      unawaited(_installerSubscription?.cancel());
    });
    return const AppUpdateViewState();
  }

  Future<void> checkIfDue() async {
    final DateTime? lastAttempt = _lastCheckAttempt;
    if (lastAttempt != null &&
        _clock().difference(lastAttempt) < automaticCheckInterval) {
      return;
    }
    await check();
  }

  Future<void> check({bool replaceCurrent = false}) async {
    if (!replaceCurrent && state.checkStatus is OperationInProgress) return;
    final (RequestCancellation cancellation, int generation) = _beginRequest();
    _lastCheckAttempt = _clock();
    state = state.copyWith(checkStatus: const OperationStatus.inProgress());
    try {
      final UpdateCatalog catalog = await cancellation.run(
        _repository.checkForUpdates,
      );
      if (!_isCurrent(cancellation, generation)) return;
      state = state.copyWith(
        supported: true,
        catalog: catalog,
        checkStatus: const OperationStatus.idle(),
      );
    } on AppUpdateUnsupportedException catch (error) {
      if (!_isCurrent(cancellation, generation)) return;
      state = state.copyWith(
        supported: false,
        checkStatus: OperationStatus.failed(error),
      );
    } on Object catch (error) {
      if (!_isCurrent(cancellation, generation) ||
          error is RequestCancelledException) {
        return;
      }
      state = state.copyWith(checkStatus: OperationStatus.failed(error));
    } finally {
      if (_isCurrent(cancellation, generation)) _cancellation = null;
    }
  }

  Future<void> install() async {
    final UpdateCandidate? candidate = state.catalog?.candidate;
    if (candidate == null ||
        state.installPhase is UpdateInstallDownloading ||
        state.installPhase is UpdateInstallWaitingForSystem) {
      return;
    }
    try {
      if (!await _repository.canRequestPackageInstalls()) {
        state = state.copyWith(
          installPhase: const UpdateInstallPermissionRequired(),
        );
        return;
      }
      final (RequestCancellation cancellation, int generation) =
          _beginRequest();
      state = state.copyWith(installPhase: const UpdateInstallDownloading(0));
      await cancellation.run(
        () => _repository.downloadAndInstall(
          candidate,
          onProgress: (double progress) {
            if (_isCurrent(cancellation, generation)) {
              state = state.copyWith(
                installPhase: UpdateInstallDownloading(progress),
              );
            }
          },
        ),
      );
      if (!_isCurrent(cancellation, generation)) return;
      _cancellation = null;
      state = state.copyWith(
        installPhase: const UpdateInstallWaitingForSystem(
          needsConfirmation: false,
        ),
      );
    } on AppUpdatePermissionRequiredException {
      state = state.copyWith(
        installPhase: const UpdateInstallPermissionRequired(),
      );
    } on Object catch (error) {
      if (error is RequestCancelledException) return;
      state = state.copyWith(installPhase: UpdateInstallFailure(error));
    }
  }

  Future<void> openInstallPermissionSettings() =>
      _repository.openPackageInstallSettings();

  Future<void> handleResumed() async {
    if (state.installPhase is UpdateInstallPermissionRequired &&
        await _repository.canRequestPackageInstalls()) {
      state = state.copyWith(installPhase: const UpdateInstallIdle());
    }
    await checkIfDue();
  }

  (RequestCancellation, int) _beginRequest() {
    _cancellation?.cancel();
    final RequestCancellation cancellation = RequestCancellation();
    _cancellation = cancellation;
    _generation += 1;
    return (cancellation, _generation);
  }

  bool _isCurrent(RequestCancellation cancellation, int generation) =>
      !cancellation.isCancelled &&
      identical(_cancellation, cancellation) &&
      _generation == generation;

  void _handleInstallerEvent(UpdateInstallerEvent event) {
    state = state.copyWith(
      installPhase: switch (event) {
        UpdateInstallerAwaitingUserAction() =>
          const UpdateInstallWaitingForSystem(needsConfirmation: true),
        UpdateInstallerInstalling() => const UpdateInstallWaitingForSystem(
          needsConfirmation: false,
        ),
        UpdateInstallerSucceeded() => const UpdateInstallComplete(),
        UpdateInstallerCancelled() => UpdateInstallFailure(event),
        UpdateInstallerFailed() => UpdateInstallFailure(event),
      },
    );
  }
}
