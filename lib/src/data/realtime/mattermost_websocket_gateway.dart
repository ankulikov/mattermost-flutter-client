import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:mattermost_flutter/src/data/realtime/network_availability_monitor.dart';
import 'package:mattermost_flutter/src/data/realtime/websocket_gateway.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final class MattermostWebSocketGateway
    implements ReconnectableWebSocketGateway {
  MattermostWebSocketGateway({
    WebSocketConnector? connector,
    Duration Function(int attempt)? retryDelay,
    NetworkAvailabilityMonitor? networkMonitor,
    this.connectionTimeout = const Duration(seconds: 15),
    this.authenticationTimeout = const Duration(seconds: 15),
  }) : _connector = connector ?? _connect,
       _retryDelay = retryDelay ?? _defaultRetryDelay,
       _networkMonitor = networkMonitor;

  final WebSocketConnector _connector;
  final Duration Function(int attempt) _retryDelay;
  final NetworkAvailabilityMonitor? _networkMonitor;
  final Set<void Function()> _reconnectCallbacks = <void Function()>{};
  final Duration connectionTimeout;
  final Duration authenticationTimeout;

  @override
  void reconnect() {
    for (final void Function() callback in List<void Function()>.of(
      _reconnectCallbacks,
    )) {
      callback();
    }
  }

  @override
  Stream<WebSocketGatewaySignal> watch({
    required Uri serverUrl,
    required String token,
    required bool Function(String eventName) acceptsEvent,
    required bool Function(String channelId) acceptsChannel,
  }) {
    late final StreamController<WebSocketGatewaySignal> controller;
    final Completer<void> stopped = Completer<void>();
    WebSocketConnection? activeConnection;
    StreamSubscription<Object?>? activeSubscription;
    StreamSubscription<NetworkAvailability>? networkSubscription;
    Completer<void>? reconnectRequested;
    var networkAvailable = true;
    var networkRevision = 0;
    WebSocketConnectionStatus? lastConnectionStatus;

    void requestReconnect() {
      final Completer<void>? current = reconnectRequested;
      if (current != null && !current.isCompleted) current.complete();
    }

    void updateNetworkAvailability(NetworkAvailability availability) {
      networkRevision += 1;
      final bool next = availability == NetworkAvailability.available;
      if (next == networkAvailable) return;
      networkAvailable = next;
      requestReconnect();
    }

    void emitConnectionStatus(
      WebSocketConnectionStatus status, {
      bool isReconnect = false,
    }) {
      if (lastConnectionStatus == status && !isReconnect) return;
      lastConnectionStatus = status;
      _add(
        controller,
        stopped,
        WebSocketConnectionSignal(status: status, isReconnect: isReconnect),
      );
    }

    Future<void> closeActive() async {
      try {
        await activeSubscription?.cancel();
      } on Object {
        // Closing is best-effort; reconnect/cancellation must still finish.
      }
      activeSubscription = null;
      try {
        await activeConnection?.close();
      } on Object {
        // The peer may already have closed the socket.
      }
      activeConnection = null;
    }

    Future<void> stop() async {
      if (!stopped.isCompleted) stopped.complete();
      _reconnectCallbacks.remove(requestReconnect);
      try {
        await networkSubscription?.cancel();
      } on Object {
        // A platform connectivity stream may already be unavailable.
      }
      await closeActive();
    }

    Future<void> run() async {
      var attempt = 0;
      var hasConnected = false;
      while (!stopped.isCompleted) {
        final Completer<void> reconnect = Completer<void>();
        reconnectRequested = reconnect;
        if (!networkAvailable) {
          emitConnectionStatus(WebSocketConnectionStatus.disconnected);
          await Future.any(<Future<void>>[stopped.future, reconnect.future]);
          continue;
        }
        emitConnectionStatus(WebSocketConnectionStatus.connecting);
        final Completer<void> authenticated = Completer<void>();
        final Completer<void> disconnected = Completer<void>();
        var lastSequence = -1;
        try {
          final WebSocketConnection connection = _connector(
            _webSocketUri(serverUrl),
          );
          activeConnection = connection;
          await Future.any(<Future<void>>[
            connection.ready,
            stopped.future,
            reconnect.future,
          ]).timeout(connectionTimeout);
          if (stopped.isCompleted) break;
          if (reconnect.isCompleted) {
            throw StateError('WebSocket reconnect requested');
          }
          activeSubscription = connection.messages.listen(
            (Object? raw) {
              try {
                final Map<String, Object?> envelope = _decodeEnvelope(raw);
                if (_isAuthenticationResponse(envelope)) {
                  if (_authenticationSucceeded(envelope)) {
                    if (!authenticated.isCompleted) authenticated.complete();
                  } else if (!authenticated.isCompleted) {
                    authenticated.completeError(
                      const FormatException('WebSocket authentication failed'),
                    );
                  }
                  return;
                }
                final MattermostWebSocketEvent? event = _decodeEvent(envelope);
                if (event == null) return;
                if (event.sequence <= lastSequence) return;
                if (event.sequence > lastSequence + 1) {
                  _add(
                    controller,
                    stopped,
                    WebSocketSequenceGapSignal(
                      expected: lastSequence + 1,
                      actual: event.sequence,
                    ),
                  );
                }
                lastSequence = event.sequence;
                if (!acceptsEvent(event.name)) return;
                final String channelId = event.channelId;
                if (_isChannelContentEvent(event.name) &&
                    channelId.isNotEmpty &&
                    !acceptsChannel(channelId)) {
                  return;
                }
                _add(controller, stopped, WebSocketEventSignal(event));
              } on Object {
                // Invalid envelopes are isolated to a single event. A later
                // sequence gap still triggers authoritative REST recovery.
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!disconnected.isCompleted) disconnected.complete();
            },
            onDone: () {
              if (!disconnected.isCompleted) disconnected.complete();
            },
            cancelOnError: true,
          );
          connection.send(
            jsonEncode(<String, Object?>{
              'seq': 1,
              'action': 'authentication_challenge',
              'data': <String, Object?>{'token': token},
            }),
          );
          await Future.any(<Future<void>>[
            authenticated.future,
            disconnected.future.then<void>(
              (_) => throw StateError('Socket closed before authentication'),
            ),
            stopped.future,
            reconnect.future.then<void>(
              (_) => throw StateError('WebSocket reconnect requested'),
            ),
          ]).timeout(authenticationTimeout);
          if (stopped.isCompleted) break;
          if (!authenticated.isCompleted) {
            throw StateError('Socket closed before authentication');
          }
          emitConnectionStatus(
            WebSocketConnectionStatus.connected,
            isReconnect: hasConnected,
          );
          hasConnected = true;
          attempt = 0;
          await Future.any(<Future<void>>[
            disconnected.future,
            stopped.future,
            reconnect.future,
          ]);
        } on Object {
          // Connection/authentication failures use the same bounded reconnect
          // path. No token, payload or personal data is logged here.
        } finally {
          await closeActive();
        }
        if (stopped.isCompleted) break;
        if (networkAvailable && reconnect.isCompleted) continue;
        emitConnectionStatus(WebSocketConnectionStatus.disconnected);
        if (!networkAvailable) continue;
        attempt++;
        await Future.any(<Future<void>>[
          Future<void>.delayed(_retryDelay(attempt)),
          stopped.future,
          reconnect.future,
        ]);
      }
      if (!controller.isClosed) await controller.close();
    }

    controller = StreamController<WebSocketGatewaySignal>(
      onListen: () {
        _reconnectCallbacks.add(requestReconnect);
        final NetworkAvailabilityMonitor? networkMonitor = _networkMonitor;
        networkSubscription = networkMonitor?.changes.listen(
          updateNetworkAvailability,
          onError: (Object error, StackTrace stackTrace) {
            // Connectivity is only an optimization. Socket close/error and
            // bounded retry remain authoritative when the plugin is missing.
          },
        );
        unawaited(() async {
          if (networkMonitor != null) {
            final int revisionBeforeCheck = networkRevision;
            try {
              final NetworkAvailability initial = await networkMonitor.current;
              if (revisionBeforeCheck == networkRevision) {
                updateNetworkAvailability(initial);
              }
            } on Object {
              // A failed radio-status check must not prevent socket attempts.
            }
          }
          if (!stopped.isCompleted) await run();
        }());
      },
      onCancel: stop,
    );
    return controller.stream;
  }

  static WebSocketConnection _connect(Uri uri) =>
      _WebSocketChannelConnection(WebSocketChannel.connect(uri));

  static Duration _defaultRetryDelay(int attempt) {
    final int exponent = min(attempt - 1, 5);
    final int baseMilliseconds = 500 * (1 << exponent);
    final int jitter = Random().nextInt(max(1, baseMilliseconds ~/ 2));
    return Duration(milliseconds: min(30000, baseMilliseconds + jitter));
  }

  static Uri _webSocketUri(Uri serverUrl) {
    final String scheme = switch (serverUrl.scheme) {
      'https' => 'wss',
      'http' => 'ws',
      final String value => value,
    };
    final String basePath = serverUrl.path.replaceAll(RegExp(r'/$'), '');
    return serverUrl.replace(
      scheme: scheme,
      path: '$basePath/api/v4/websocket',
      query: null,
      fragment: null,
    );
  }

  static void _add(
    StreamController<WebSocketGatewaySignal> controller,
    Completer<void> stopped,
    WebSocketGatewaySignal signal,
  ) {
    if (!stopped.isCompleted && !controller.isClosed) controller.add(signal);
  }

  static Map<String, Object?> _decodeEnvelope(Object? raw) {
    final Object? decoded = switch (raw) {
      final String value => jsonDecode(value),
      final List<int> value => jsonDecode(utf8.decode(value)),
      _ => raw,
    };
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('Invalid WebSocket envelope');
    }
    return decoded.map(
      (Object? key, Object? value) => MapEntry<String, Object?>(
        key is String ? key : key.toString(),
        value,
      ),
    );
  }

  static bool _isAuthenticationResponse(Map<String, Object?> envelope) =>
      envelope['seq_reply'] == 1 && envelope['status'] is String;

  static bool _authenticationSucceeded(Map<String, Object?> envelope) =>
      envelope['status'] == 'OK';

  static bool _isChannelContentEvent(String name) => switch (name) {
    'posted' || 'post_edited' || 'post_deleted' => true,
    _ => false,
  };

  static MattermostWebSocketEvent? _decodeEvent(Map<String, Object?> envelope) {
    final Object? name = envelope['event'];
    final Object? sequence = envelope['seq'];
    if (name is! String || sequence is! num) return null;
    return MattermostWebSocketEvent(
      name: name,
      sequence: sequence.toInt(),
      data: _stringMap(envelope['data']),
      broadcast: _stringMap(envelope['broadcast']),
    );
  }

  static Map<String, Object?> _stringMap(Object? value) {
    if (value is! Map<Object?, Object?>) return const <String, Object?>{};
    return value.map(
      (Object? key, Object? item) =>
          MapEntry<String, Object?>(key is String ? key : key.toString(), item),
    );
  }
}

final class _WebSocketChannelConnection implements WebSocketConnection {
  const _WebSocketChannelConnection(this._channel);

  final WebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<Object?> get messages => _channel.stream;

  @override
  void send(Object? message) => _channel.sink.add(message);

  @override
  Future<void> close() async => _channel.sink.close();
}
