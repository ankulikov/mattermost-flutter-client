import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/providers/infrastructure_providers.dart';
import 'package:mattermost_flutter/src/data/providers/session_providers.dart';
import 'package:mattermost_flutter/src/data/realtime/session_realtime_service.dart';
import 'package:mattermost_flutter/src/data/realtime/websocket_gateway.dart';
import 'package:mattermost_flutter/src/data/storage/credential_store.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/services/realtime_connection_service.dart';

void main() {
  final AuthSession session = AuthSession(
    serverUrl: Uri(scheme: 'https', host: 'chat.example.test'),
    userId: 'me',
    username: 'me',
  );

  test(
    'fans subscribers out from one socket and filters per subscriber',
    () async {
      final _Gateway gateway = _Gateway();
      final SessionRealtimeService service = SessionRealtimeService(
        gateway: gateway,
        credentialStore: const _Credentials(),
      );
      addTearDown(service.dispose);
      final List<SessionRealtimeSignal> inbox = <SessionRealtimeSignal>[];
      final List<SessionRealtimeSignal> actions = <SessionRealtimeSignal>[];
      final subscriptions = <StreamSubscription<SessionRealtimeSignal>>[
        service
            .watch(
              session: session,
              subscription: const SessionRealtimeSubscription(
                eventNames: <String>{'posted'},
              ),
            )
            .listen(inbox.add),
        service
            .watch(
              session: session,
              subscription: const SessionRealtimeSubscription(
                eventNames: <String>{'ephemeral_message'},
              ),
            )
            .listen(actions.add),
      ];
      addTearDown(() async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      });
      await _waitUntil(() => gateway.watchCalls == 1);

      gateway.add(_event('posted', 1));
      gateway.add(_event('ephemeral_message', 2));
      await _waitUntil(
        () =>
            inbox.whereType<SessionRealtimeEventReceived>().length == 1 &&
            actions.whereType<SessionRealtimeEventReceived>().length == 1,
      );

      expect(gateway.watchCalls, 1);
      expect(
        inbox.whereType<SessionRealtimeEventReceived>().single.event.name,
        'posted',
      );
      expect(
        actions.whereType<SessionRealtimeEventReceived>().single.event.name,
        'ephemeral_message',
      );
    },
  );

  test(
    'turns reconnect and sequence gap into shared recovery signals',
    () async {
      final _Gateway gateway = _Gateway();
      final SessionRealtimeService service = SessionRealtimeService(
        gateway: gateway,
        credentialStore: const _Credentials(),
      );
      addTearDown(service.dispose);
      final List<SessionRealtimeSignal> values = <SessionRealtimeSignal>[];
      final StreamSubscription<SessionRealtimeSignal> subscription = service
          .watch(
            session: session,
            subscription: const SessionRealtimeSubscription(
              eventNames: <String>{},
            ),
          )
          .listen(values.add);
      addTearDown(subscription.cancel);
      await _waitUntil(() => gateway.watchCalls == 1);

      gateway.add(
        const WebSocketConnectionSignal(
          status: WebSocketConnectionStatus.connected,
          isReconnect: true,
        ),
      );
      gateway.add(const WebSocketSequenceGapSignal(expected: 2, actual: 4));
      await _waitUntil(
        () => values.whereType<SessionRealtimeRecoveryRequired>().length == 2,
      );
    },
  );

  test('starts from the active session without a feature subscriber', () async {
    final _Gateway gateway = _Gateway();
    final SessionRealtimeService service = SessionRealtimeService(
      gateway: gateway,
      credentialStore: const _Credentials(),
    );
    addTearDown(service.dispose);

    await service.setSession(session);

    expect(gateway.watchCalls, 1);
  });

  test('provider starts realtime when an account becomes active', () async {
    final _Gateway gateway = _Gateway();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        webSocketGatewayProvider.overrideWithValue(gateway),
        credentialStoreProvider.overrideWithValue(const _Credentials()),
      ],
    );
    addTearDown(container.dispose);
    final SessionRealtimeService service = container.read(
      sessionRealtimeServiceProvider,
    );

    container.read(activeAccountSessionProvider.notifier).set(session);
    await _waitUntil(() => gateway.watchCalls == 1);

    expect(service.connectionStatus, RealtimeConnectionStatus.connecting);
  });

  test('replays the current connection status to late subscribers', () async {
    final _Gateway gateway = _Gateway();
    final SessionRealtimeService service = SessionRealtimeService(
      gateway: gateway,
      credentialStore: const _Credentials(),
    );
    addTearDown(service.dispose);
    await service.setSession(session);
    gateway.add(
      const WebSocketConnectionSignal(
        status: WebSocketConnectionStatus.connected,
      ),
    );
    await _waitUntil(
      () => service.connectionStatus == RealtimeConnectionStatus.connected,
    );

    expect(
      await service.connectionStatuses.first,
      RealtimeConnectionStatus.connected,
    );
  });
}

WebSocketEventSignal _event(String name, int sequence) => WebSocketEventSignal(
  MattermostWebSocketEvent(
    name: name,
    sequence: sequence,
    data: const <String, Object?>{},
    broadcast: const <String, Object?>{},
  ),
);

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached');
}

final class _Gateway implements WebSocketGateway {
  final StreamController<WebSocketGatewaySignal> _controller =
      StreamController<WebSocketGatewaySignal>.broadcast();
  int watchCalls = 0;

  @override
  Stream<WebSocketGatewaySignal> watch({
    required Uri serverUrl,
    required String token,
    required bool Function(String eventName) acceptsEvent,
    required bool Function(String channelId) acceptsChannel,
  }) {
    watchCalls += 1;
    return _controller.stream;
  }

  void add(WebSocketGatewaySignal signal) => _controller.add(signal);
}

final class _Credentials implements CredentialStore {
  const _Credentials();

  @override
  Future<void> clear() async {}

  @override
  Future<({Uri serverUrl, String token})?> read() async =>
      (serverUrl: Uri.parse('https://chat.example.test'), token: 'secret');

  @override
  Future<void> save({required Uri serverUrl, required String token}) async {}
}
