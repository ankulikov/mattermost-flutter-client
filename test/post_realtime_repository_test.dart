import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/data/realtime/session_realtime_service.dart';
import 'package:mattermost_flutter/src/data/realtime/websocket_gateway.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_post_repository.dart';
import 'package:mattermost_flutter/src/data/storage/credential_store.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';

import 'support/fake_user_repository.dart';

void main() {
  test(
    'maps shared websocket post events into channel domain events',
    () async {
      final _Gateway gateway = _Gateway();
      final SessionRealtimeService realtime = SessionRealtimeService(
        gateway: gateway,
        credentialStore: _Credentials(_session.serverUrl),
      );
      final MattermostPostRepository repository = MattermostPostRepository(
        api: _Api(),
        messageMapper: const MattermostMessageMapper(),
        users: FakeUserRepository(),
        realtime: realtime,
      );
      final List<PostRealtimeEvent> events = <PostRealtimeEvent>[];
      final StreamSubscription<PostRealtimeEvent> subscription = repository
          .watchRealtime(session: _session, channelId: 'channel-1')
          .listen(events.add);
      addTearDown(() async {
        await subscription.cancel();
        await realtime.dispose();
        await gateway.close();
      });
      await _waitUntil(() => gateway.started);

      gateway.add(_postSignal('posted', id: 'post-1', message: 'created'));
      gateway.add(
        _postSignal(
          'posted',
          id: 'other',
          message: 'other',
          channelId: 'channel-2',
        ),
      );
      gateway.add(_postSignal('post_edited', id: 'post-1', message: 'edited'));
      gateway.add(
        _postSignal(
          'post_deleted',
          id: 'post-1',
          message: 'edited',
          deleteAt: 4,
        ),
      );
      gateway.add(const WebSocketSequenceGapSignal(expected: 5, actual: 6));

      await _waitUntil(() => events.length == 4);
      expect(events[0], isA<PostRealtimeUpserted>());
      expect((events[0] as PostRealtimeUpserted).post.message, 'created');
      expect((events[1] as PostRealtimeUpserted).post.message, 'edited');
      expect(
        (events[1] as PostRealtimeUpserted).post.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(3),
      );
      expect((events[2] as PostRealtimeDeleted).post.isDeleted, isTrue);
      expect(events[3], isA<PostRealtimeRecoveryRequired>());
    },
  );

  test('filters a thread subscription before resolving authors', () async {
    final _Gateway gateway = _Gateway();
    final SessionRealtimeService realtime = SessionRealtimeService(
      gateway: gateway,
      credentialStore: _Credentials(_session.serverUrl),
    );
    final FakeUserRepository users = FakeUserRepository();
    final MattermostPostRepository repository = MattermostPostRepository(
      api: _Api(),
      messageMapper: const MattermostMessageMapper(),
      users: users,
      realtime: realtime,
    );
    final List<PostRealtimeEvent> events = <PostRealtimeEvent>[];
    final StreamSubscription<PostRealtimeEvent> subscription = repository
        .watchRealtime(session: _session, rootPostId: 'root-1')
        .listen(events.add);
    addTearDown(() async {
      await subscription.cancel();
      await realtime.dispose();
      await gateway.close();
    });
    await _waitUntil(() => gateway.started);

    gateway.add(_postSignal('posted', id: 'unrelated', message: 'ignore'));
    gateway.add(
      _postSignal('posted', id: 'reply-1', message: 'reply', rootId: 'root-1'),
    );

    await _waitUntil(() => events.length == 1);
    expect((events.single as PostRealtimeUpserted).post.id, 'reply-1');
  });

  test('maps reaction websocket events into post reaction deltas', () async {
    final _Gateway gateway = _Gateway();
    final SessionRealtimeService realtime = SessionRealtimeService(
      gateway: gateway,
      credentialStore: _Credentials(_session.serverUrl),
    );
    final MattermostPostRepository repository = MattermostPostRepository(
      api: _Api(),
      messageMapper: const MattermostMessageMapper(),
      users: FakeUserRepository(),
      realtime: realtime,
    );
    final List<PostRealtimeEvent> events = <PostRealtimeEvent>[];
    final StreamSubscription<PostRealtimeEvent> subscription = repository
        .watchRealtime(session: _session, channelId: 'channel-1')
        .listen(events.add);
    addTearDown(() async {
      await subscription.cancel();
      await realtime.dispose();
      await gateway.close();
    });
    await _waitUntil(() => gateway.started);

    gateway.add(_reactionSignal('reaction_added'));
    gateway.add(_reactionSignal('reaction_removed'));

    await _waitUntil(() => events.length == 2);
    expect(
      events[0],
      isA<PostRealtimeReactionChanged>()
          .having(
            (PostRealtimeReactionChanged event) => event.postId,
            'post',
            'post-1',
          )
          .having(
            (PostRealtimeReactionChanged event) => event.userId,
            'user',
            'grace',
          )
          .having(
            (PostRealtimeReactionChanged event) => event.emojiName,
            'emoji',
            'wave',
          )
          .having(
            (PostRealtimeReactionChanged event) => event.added,
            'added',
            isTrue,
          ),
    );
    expect((events[1] as PostRealtimeReactionChanged).added, isFalse);
  });
}

final AuthSession _session = AuthSession(
  serverUrl: Uri.parse('https://chat.example.com'),
  userId: 'me',
  username: 'current',
);

WebSocketEventSignal _postSignal(
  String name, {
  required String id,
  required String message,
  String channelId = 'channel-1',
  String rootId = '',
  int deleteAt = 0,
}) {
  final int sequence = switch (name) {
    'posted' => id == 'post-1' ? 1 : 2,
    'post_edited' => 3,
    'post_deleted' => 4,
    _ => 1,
  };
  return WebSocketEventSignal(
    MattermostWebSocketEvent(
      name: name,
      sequence: sequence,
      data: <String, Object?>{
        'post': jsonEncode(<String, Object?>{
          'id': id,
          'user_id': 'ada',
          'channel_id': channelId,
          'message': message,
          'create_at': 1,
          'update_at': sequence,
          'delete_at': deleteAt,
          'root_id': rootId,
        }),
      },
      broadcast: <String, Object?>{'channel_id': channelId},
    ),
  );
}

WebSocketEventSignal _reactionSignal(String name) => WebSocketEventSignal(
  MattermostWebSocketEvent(
    name: name,
    sequence: name == 'reaction_added' ? 1 : 2,
    data: <String, Object?>{
      'reaction': jsonEncode(<String, Object?>{
        'user_id': 'grace',
        'post_id': 'post-1',
        'emoji_name': 'wave',
        'create_at': 1,
      }),
    },
    broadcast: const <String, Object?>{'channel_id': 'channel-1'},
  ),
);

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not reached');
}

final class _Api extends Fake implements MattermostApi {}

final class _Credentials implements CredentialStore {
  const _Credentials(this.serverUrl);

  final Uri serverUrl;

  @override
  Future<({Uri serverUrl, String token})?> read() async =>
      (serverUrl: serverUrl, token: 'token');

  @override
  Future<void> clear() async {}

  @override
  Future<void> save({required Uri serverUrl, required String token}) async {}
}

final class _Gateway implements WebSocketGateway {
  final StreamController<WebSocketGatewaySignal> _signals =
      StreamController<WebSocketGatewaySignal>();
  bool started = false;

  @override
  Stream<WebSocketGatewaySignal> watch({
    required Uri serverUrl,
    required String token,
    required bool Function(String eventName) acceptsEvent,
    required bool Function(String channelId) acceptsChannel,
  }) {
    started = true;
    return _signals.stream;
  }

  void add(WebSocketGatewaySignal signal) => _signals.add(signal);

  Future<void> close() => _signals.close();
}
