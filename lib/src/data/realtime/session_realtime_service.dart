import 'dart:async';

import 'package:mattermost_flutter/src/data/realtime/websocket_gateway.dart';
import 'package:mattermost_flutter/src/data/storage/credential_store.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/services/realtime_connection_service.dart';

/// A feature's interest in the session-wide Mattermost event stream.
///
/// Event names remain transport strings because Mattermost can add server and
/// plugin events without requiring the shared connection owner to change.
final class SessionRealtimeSubscription {
  const SessionRealtimeSubscription({
    required this.eventNames,
    this.acceptsChannel,
  });

  final Set<String> eventNames;
  final bool Function(String channelId)? acceptsChannel;

  bool accepts(MattermostWebSocketEvent event) {
    if (!eventNames.contains(event.name)) return false;
    final bool Function(String channelId)? channelFilter = acceptsChannel;
    final String channelId = event.channelId;
    return channelFilter == null ||
        channelId.isEmpty ||
        channelFilter(channelId);
  }
}

/// Named event groups for current and future feature subscriptions.
abstract final class MattermostRealtimeEventGroups {
  static const Set<String> posts = <String>{
    'posted',
    'post_edited',
    'post_deleted',
  };
  static const Set<String> threads = <String>{'thread_updated'};
  static const Set<String> userStatus = <String>{'status_change'};
  static const Set<String> preferences = <String>{
    'preference_changed',
    'preferences_changed',
    'preferences_deleted',
  };
  static const Set<String> ephemeral = <String>{'ephemeral_message'};
}

sealed class SessionRealtimeSignal {
  const SessionRealtimeSignal();
}

final class SessionRealtimeConnectionChanged extends SessionRealtimeSignal {
  const SessionRealtimeConnectionChanged(this.status);

  final WebSocketConnectionStatus status;
}

final class SessionRealtimeRecoveryRequired extends SessionRealtimeSignal {
  const SessionRealtimeRecoveryRequired();
}

final class SessionRealtimeEventReceived extends SessionRealtimeSignal {
  const SessionRealtimeEventReceived(this.event);

  final MattermostWebSocketEvent event;
}

/// Owns one authenticated WebSocket and fans its decoded signals out to all
/// session features. Feature repositories map events into domain models.
final class SessionRealtimeService implements RealtimeConnectionService {
  SessionRealtimeService({
    required WebSocketGateway gateway,
    required CredentialStore credentialStore,
  }) : _gateway = gateway,
       _credentialStore = credentialStore;

  final WebSocketGateway _gateway;
  final CredentialStore _credentialStore;
  final StreamController<SessionRealtimeSignal> _signals =
      StreamController<SessionRealtimeSignal>.broadcast();
  StreamSubscription<WebSocketGatewaySignal>? _subscription;
  AuthSession? _session;
  var _generation = 0;
  bool _disposed = false;
  WebSocketConnectionStatus _connectionStatus =
      WebSocketConnectionStatus.disconnected;

  Stream<SessionRealtimeSignal> watch({
    required AuthSession session,
    required SessionRealtimeSubscription subscription,
  }) {
    return Stream<SessionRealtimeSignal>.multi((controller) {
      unawaited(setSession(session));
      controller.add(SessionRealtimeConnectionChanged(_connectionStatus));
      final StreamSubscription<SessionRealtimeSignal> signalSubscription =
          _signals.stream.listen(
            (SessionRealtimeSignal signal) {
              if (signal case SessionRealtimeEventReceived(:final event)) {
                if (!subscription.accepts(event)) return;
              }
              controller.add(signal);
            },
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = signalSubscription.cancel;
    });
  }

  @override
  RealtimeConnectionStatus get connectionStatus =>
      _mapConnectionStatus(_connectionStatus);

  @override
  Stream<RealtimeConnectionStatus> get connectionStatuses =>
      Stream<RealtimeConnectionStatus>.multi((controller) {
        controller.add(connectionStatus);
        final StreamSubscription<SessionRealtimeSignal> signalSubscription =
            _signals.stream.listen(
              (SessionRealtimeSignal signal) {
                if (signal case SessionRealtimeConnectionChanged(
                  :final status,
                )) {
                  controller.add(_mapConnectionStatus(status));
                }
              },
              onError: controller.addError,
              onDone: controller.close,
            );
        controller.onCancel = signalSubscription.cancel;
      }).distinct();

  @override
  void reconnect() {
    if (_session == null || _disposed) return;
    if (_subscription == null) {
      unawaited(setSession(_session));
      return;
    }
    final WebSocketGateway gateway = _gateway;
    if (gateway is ReconnectableWebSocketGateway) gateway.reconnect();
  }

  /// Starts the single socket for [session], or stops it when session is null.
  Future<void> setSession(AuthSession? session) async {
    if (_disposed) return;
    if (session != null &&
        _session?.durableDataScopeId == session.durableDataScopeId &&
        _subscription != null) {
      return;
    }
    final int generation = ++_generation;
    _session = session;
    final StreamSubscription<WebSocketGatewaySignal>? previous = _subscription;
    _subscription = null;
    try {
      await previous?.cancel();
    } on Object {
      // A dead platform socket must not block the replacement connection.
    }
    if (_disposed || generation != _generation) return;
    if (session == null) {
      _emitConnectionStatus(WebSocketConnectionStatus.disconnected);
      return;
    }
    await _start(session, generation);
  }

  Future<void> _start(AuthSession session, int generation) async {
    _emitConnectionStatus(WebSocketConnectionStatus.connecting);
    final ({Uri serverUrl, String token})? credentials;
    try {
      credentials = await _credentialStore.read();
    } on Object {
      if (!_disposed && generation == _generation) {
        _emitConnectionStatus(WebSocketConnectionStatus.disconnected);
      }
      return;
    }
    if (_disposed || generation != _generation) return;
    if (credentials == null || credentials.serverUrl != session.serverUrl) {
      _emitConnectionStatus(WebSocketConnectionStatus.disconnected);
      return;
    }
    _subscription = _gateway
        .watch(
          serverUrl: session.serverUrl,
          token: credentials.token,
          acceptsEvent: (_) => true,
          acceptsChannel: (_) => true,
        )
        .listen(
          (WebSocketGatewaySignal signal) {
            if (_disposed || generation != _generation) return;
            switch (signal) {
              case WebSocketConnectionSignal(:final status, :final isReconnect):
                _emitConnectionStatus(status);
                if (status == WebSocketConnectionStatus.connected &&
                    isReconnect) {
                  _signals.add(const SessionRealtimeRecoveryRequired());
                }
              case WebSocketSequenceGapSignal():
                _signals.add(const SessionRealtimeRecoveryRequired());
              case WebSocketEventSignal(:final event):
                _signals.add(SessionRealtimeEventReceived(event));
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!_disposed && generation == _generation) {
              _emitConnectionStatus(WebSocketConnectionStatus.disconnected);
            }
          },
          onDone: () {
            if (!_disposed && generation == _generation) {
              _subscription = null;
              _emitConnectionStatus(WebSocketConnectionStatus.disconnected);
            }
          },
        );
  }

  void _emitConnectionStatus(WebSocketConnectionStatus status) {
    if (_connectionStatus == status) return;
    _connectionStatus = status;
    if (!_disposed && !_signals.isClosed) {
      _signals.add(SessionRealtimeConnectionChanged(status));
    }
  }

  static RealtimeConnectionStatus _mapConnectionStatus(
    WebSocketConnectionStatus status,
  ) => switch (status) {
    WebSocketConnectionStatus.connecting => RealtimeConnectionStatus.connecting,
    WebSocketConnectionStatus.connected => RealtimeConnectionStatus.connected,
    WebSocketConnectionStatus.disconnected =>
      RealtimeConnectionStatus.disconnected,
  };

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    try {
      await _subscription?.cancel();
    } on Object {
      // Disposal remains best-effort when the platform socket already failed.
    }
    _connectionStatus = WebSocketConnectionStatus.disconnected;
    await _signals.close();
  }
}
