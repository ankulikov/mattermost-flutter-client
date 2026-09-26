/// State of a non-blocking asynchronous operation that runs while useful
/// screen data remains visible.
///
/// Unlike separate `isLoading` and `hasFailed` flags, this model cannot
/// represent contradictory states. Initial screen loading remains represented
/// by Riverpod's `AsyncValue`.
sealed class OperationStatus {
  const OperationStatus();

  const factory OperationStatus.idle() = OperationIdle;
  const factory OperationStatus.inProgress() = OperationInProgress;
  const factory OperationStatus.failed(Object error) = OperationFailed;
}

final class OperationIdle extends OperationStatus {
  const OperationIdle();
}

final class OperationInProgress extends OperationStatus {
  const OperationInProgress();
}

final class OperationFailed extends OperationStatus {
  const OperationFailed(this.error);

  final Object error;
}
