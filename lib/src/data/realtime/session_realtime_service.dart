import 'dart:async';

import 'package:mattermost_flutter/src/data/realtime/websocket_gateway.dart';
import 'package:mattermost_flutter/src/data/storage/credential_store.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';

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
final class SessionRealtimeService {
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

  Stream<SessionRealtimeSignal> watch({
    required AuthSession session,
    required Set<String> eventNames,
    bool Function(String channelId)? acceptsChannel,
  }) {
    _ensureStarted(session);
    return _signals.stream.where((SessionRealtimeSignal signal) {
      if (signal case SessionRealtimeEventReceived(:final event)) {
        if (!eventNames.contains(event.name)) return false;
        final String channelId = event.channelId;
        if (acceptsChannel != null &&
            channelId.isNotEmpty &&
            !acceptsChannel(channelId)) {
          return false;
        }
      }
      return true;
    });
  }

  void reconnect() {
    final WebSocketGateway gateway = _gateway;
    if (gateway is ReconnectableWebSocketGateway) gateway.reconnect();
  }

  void _ensureStarted(AuthSession session) {
    if (_disposed) return;
    if (_session?.durableDataScopeId == session.durableDataScopeId &&
        _subscription != null) {
      return;
    }
    final int generation = ++_generation;
    _session = session;
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_start(session, generation));
  }

  Future<void> _start(AuthSession session, int generation) async {
    final ({Uri serverUrl, String token})? credentials = await _credentialStore
        .read();
    if (_disposed || generation != _generation) return;
    if (credentials == null || credentials.serverUrl != session.serverUrl) {
      _signals.add(
        const SessionRealtimeConnectionChanged(
          WebSocketConnectionStatus.disconnected,
        ),
      );
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
                _signals.add(SessionRealtimeConnectionChanged(status));
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
              _signals.add(
                const SessionRealtimeConnectionChanged(
                  WebSocketConnectionStatus.disconnected,
                ),
              );
            }
          },
        );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    await _subscription?.cancel();
    await _signals.close();
  }
}
