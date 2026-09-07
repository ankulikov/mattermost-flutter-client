import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/realtime/mattermost_websocket_gateway.dart';
import 'package:mattermost_flutter/src/data/realtime/websocket_gateway.dart';

void main() {
  test('authenticates, filters events and reports a sequence gap', () async {
    final _Connection connection = _Connection();
    final MattermostWebSocketGateway gateway = MattermostWebSocketGateway(
      connector: (Uri uri) {
        expect(uri.toString(), 'wss://chat.example/api/v4/websocket');
        return connection;
      },
      retryDelay: (_) => Duration.zero,
    );
    final List<WebSocketGatewaySignal> signals = <WebSocketGatewaySignal>[];
    final StreamSubscription<WebSocketGatewaySignal> subscription = gateway
        .watch(
          serverUrl: Uri.parse('https://chat.example'),
          token: 'secret-token',
          acceptsEvent: (String name) => name == 'posted',
          acceptsChannel: (String id) => id == 'wanted',
        )
        .listen(signals.add);
    addTearDown(subscription.cancel);

    await _waitUntil(() => connection.sent.isNotEmpty);
    final Map<String, Object?> auth = _map(
      jsonDecode(connection.sent.single as String),
    );
    expect(auth['action'], 'authentication_challenge');
    expect(_map(auth['data'])['token'], 'secret-token');

    connection.add(<String, Object?>{'status': 'OK', 'seq_reply': 1});
    connection.add(_event('hello', 0));
    connection.add(_event('status_change', 1));
    connection.add(_event('posted', 2, channelId: 'ignored'));
    connection.add(_event('posted', 4, channelId: 'wanted'));
    await _waitUntil(
      () => signals.whereType<WebSocketEventSignal>().isNotEmpty,
    );

    expect(
      signals.whereType<WebSocketConnectionSignal>().map((it) => it.status),
      contains(WebSocketConnectionStatus.connected),
    );
    expect(signals.whereType<WebSocketSequenceGapSignal>().single.expected, 3);
    expect(signals.whereType<WebSocketSequenceGapSignal>().single.actual, 4);
    expect(
      signals.whereType<WebSocketEventSignal>().single.event.channelId,
      'wanted',
    );
  });

  test('reconnects after closure and marks the new connection', () async {
    final List<_Connection> connections = <_Connection>[
      _Connection(),
      _Connection(),
    ];
    var nextConnection = 0;
    final MattermostWebSocketGateway gateway = MattermostWebSocketGateway(
      connector: (_) => connections[nextConnection++],
      retryDelay: (_) => Duration.zero,
    );
    final List<WebSocketGatewaySignal> signals = <WebSocketGatewaySignal>[];
    final StreamSubscription<WebSocketGatewaySignal> subscription = gateway
        .watch(
          serverUrl: Uri.parse('https://chat.example'),
          token: 'token',
          acceptsEvent: (_) => false,
          acceptsChannel: (_) => false,
        )
        .listen(signals.add);
    addTearDown(subscription.cancel);

    await _waitUntil(() => connections.first.sent.isNotEmpty);
    connections.first.add(<String, Object?>{'status': 'OK', 'seq_reply': 1});
    await _waitUntil(
      () => signals.whereType<WebSocketConnectionSignal>().any(
        (it) => it.status == WebSocketConnectionStatus.connected,
      ),
    );
    await connections.first.finish();
    await _waitUntil(() => connections.last.sent.isNotEmpty);
    connections.last.add(<String, Object?>{'status': 'OK', 'seq_reply': 1});
    await _waitUntil(
      () => signals.whereType<WebSocketConnectionSignal>().any(
        (it) => it.isReconnect,
      ),
    );

    final List<WebSocketConnectionSignal> states = signals
        .whereType<WebSocketConnectionSignal>()
        .toList();
    expect(
      states.any((it) => it.status == WebSocketConnectionStatus.disconnected),
      isTrue,
    );
    expect(states.last.status, WebSocketConnectionStatus.connected);
    expect(states.last.isReconnect, isTrue);
  });

  test('replaces an active connection when reconnect is requested', () async {
    final List<_Connection> connections = <_Connection>[
      _Connection(),
      _Connection(),
    ];
    var nextConnection = 0;
    final MattermostWebSocketGateway gateway = MattermostWebSocketGateway(
      connector: (_) => connections[nextConnection++],
      retryDelay: (_) => Duration.zero,
    );
    final List<WebSocketGatewaySignal> signals = <WebSocketGatewaySignal>[];
    final StreamSubscription<WebSocketGatewaySignal> subscription = gateway
        .watch(
          serverUrl: Uri.parse('https://chat.example'),
          token: 'token',
          acceptsEvent: (_) => false,
          acceptsChannel: (_) => false,
        )
        .listen(signals.add);
    addTearDown(subscription.cancel);

    await _waitUntil(() => connections.first.sent.isNotEmpty);
    connections.first.add(<String, Object?>{'status': 'OK', 'seq_reply': 1});
    await _waitUntil(
      () => signals.whereType<WebSocketConnectionSignal>().any(
        (WebSocketConnectionSignal it) =>
            it.status == WebSocketConnectionStatus.connected,
      ),
    );

    gateway.reconnect();
    await _waitUntil(() => connections.last.sent.isNotEmpty);
    connections.last.add(<String, Object?>{'status': 'OK', 'seq_reply': 1});
    await _waitUntil(
      () => signals.whereType<WebSocketConnectionSignal>().any(
        (WebSocketConnectionSignal it) => it.isReconnect,
      ),
    );

    expect(nextConnection, 2);
    expect(
      signals.whereType<WebSocketConnectionSignal>().last.status,
      WebSocketConnectionStatus.connected,
    );
    expect(
      signals.whereType<WebSocketConnectionSignal>().last.isReconnect,
      isTrue,
    );
  });
}

Map<String, Object?> _event(
  String name,
  int sequence, {
  String channelId = '',
}) => <String, Object?>{
  'event': name,
  'seq': sequence,
  'data': const <String, Object?>{},
  'broadcast': <String, Object?>{'channel_id': channelId},
};

Map<String, Object?> _map(Object? value) =>
    (value as Map<Object?, Object?>).cast<String, Object?>();

Future<void> _waitUntil(bool Function() condition) async {
  for (var index = 0; index < 100; index++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached');
}

final class _Connection implements WebSocketConnection {
  final StreamController<Object?> _messages = StreamController<Object?>();
  final List<Object?> sent = <Object?>[];

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  void send(Object? message) => sent.add(message);

  void add(Map<String, Object?> value) => _messages.add(jsonEncode(value));

  Future<void> finish() => _messages.close();

  @override
  Future<void> close() async {}
}
