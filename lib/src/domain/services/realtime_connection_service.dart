enum RealtimeConnectionStatus { connecting, connected, disconnected }

/// Session-wide realtime connection lifecycle exposed without transport types.
abstract interface class RealtimeConnectionService {
  RealtimeConnectionStatus get connectionStatus;

  /// Replays the current state to every new listener and then emits changes.
  Stream<RealtimeConnectionStatus> get connectionStatuses;

  /// Replaces a potentially half-open connection, for example after resume.
  void reconnect();
}
