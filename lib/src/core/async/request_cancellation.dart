import 'dart:async';

typedef CancelListener = void Function(Object? reason);

/// Framework-neutral cancellation owned by a presentation lifecycle.
///
/// [run] makes the cancellation available to infrastructure without leaking a
/// Dio type through domain repository contracts.
final class RequestCancellation {
  static final Object _zoneKey = Object();

  final Set<CancelListener> _listeners = <CancelListener>{};
  bool _isCancelled = false;
  Object? _reason;

  bool get isCancelled => _isCancelled;
  Object? get reason => _reason;

  static RequestCancellation? get current =>
      Zone.current[_zoneKey] as RequestCancellation?;

  Future<T> run<T>(Future<T> Function() operation) {
    if (_isCancelled) {
      return Future<T>.error(RequestCancelledException(_reason));
    }
    return runZoned(operation, zoneValues: <Object, Object>{_zoneKey: this});
  }

  void cancel([Object? reason]) {
    if (_isCancelled) return;
    _isCancelled = true;
    _reason = reason;
    for (final CancelListener listener in _listeners.toList(growable: false)) {
      listener(reason);
    }
    _listeners.clear();
  }

  /// Registers a listener and returns a function that detaches it.
  void Function() addListener(CancelListener listener) {
    if (_isCancelled) {
      listener(_reason);
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

final class RequestCancelledException implements Exception {
  const RequestCancelledException(this.reason);

  final Object? reason;
}
