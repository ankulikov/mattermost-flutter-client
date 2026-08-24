enum SyncPhase { idle, syncing, offline, failed }

final class SyncState {
  const SyncState({
    this.phase = SyncPhase.idle,
    this.lastSuccessfulSync,
    this.error,
  });

  final SyncPhase phase;
  final DateTime? lastSuccessfulSync;
  final Object? error;
}
