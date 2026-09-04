import 'dart:async';

/// Transport-only connection state. Feature repositories map this to their
/// own domain state instead of exposing the WebSocket package to presentation.
enum WebSocketConnectionStatus { connecting, connected, disconnected }

sealed class WebSocketGatewaySignal {
  const WebSocketGatewaySignal();
}

final class WebSocketConnectionSignal extends WebSocketGatewaySignal {
  const WebSocketConnectionSignal({
    required this.status,
    this.isReconnect = false,
  });

  final WebSocketConnectionStatus status;
  final bool isReconnect;
}

final class WebSocketEventSignal extends WebSocketGatewaySignal {
  const WebSocketEventSignal(this.event);

  final MattermostWebSocketEvent event;
}

final class WebSocketSequenceGapSignal extends WebSocketGatewaySignal {
  const WebSocketSequenceGapSignal({
    required this.expected,
    required this.actual,
  });

  final int expected;
  final int actual;
}

/// A decoded Mattermost WebSocket envelope without feature-specific mapping.
final class MattermostWebSocketEvent {
  const MattermostWebSocketEvent({
    required this.name,
    required this.sequence,
    required this.data,
    required this.broadcast,
  });

  final String name;
  final int sequence;
  final Map<String, Object?> data;
  final Map<String, Object?> broadcast;

  String get channelId {
    final Object? broadcastChannel = broadcast['channel_id'];
    if (broadcastChannel is String && broadcastChannel.isNotEmpty) {
      return broadcastChannel;
    }
    final Object? dataChannel = data['channel_id'];
    return dataChannel is String ? dataChannel : '';
  }
}

abstract interface class WebSocketGateway {
  /// Connects asynchronously and keeps reconnecting until the returned stream
  /// is cancelled. Only event names and channels accepted by the callbacks are
  /// forwarded, while sequence tracking still observes every server event.
  Stream<WebSocketGatewaySignal> watch({
    required Uri serverUrl,
    required String token,
    required bool Function(String eventName) acceptsEvent,
    required bool Function(String channelId) acceptsChannel,
  });
}

/// Small injectable boundary around a concrete WebSocket implementation.
abstract interface class WebSocketConnection {
  Future<void> get ready;
  Stream<Object?> get messages;
  void send(Object? message);
  Future<void> close();
}

typedef WebSocketConnector = WebSocketConnection Function(Uri uri);
