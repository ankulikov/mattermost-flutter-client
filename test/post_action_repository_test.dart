import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/data/realtime/session_realtime_service.dart';
import 'package:mattermost_flutter/src/data/realtime/websocket_gateway.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_post_action_repository.dart';
import 'package:mattermost_flutter/src/data/storage/credential_store.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/post_action.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';

import 'support/fake_user_repository.dart';

void main() {
  test(
    'dispatches with its opaque cookie then maps the refreshed post',
    () async {
      final _ActionApi api = _ActionApi();
      final MattermostPostActionRepository repository =
          MattermostPostActionRepository(
            api: api,
            messageMapper: const MattermostMessageMapper(),
            users: FakeUserRepository(),
          );

      final result = await repository.execute(
        session: AuthSession(
          serverUrl: Uri.parse('https://chat.example.com'),
          userId: 'me',
          username: 'me',
        ),
        postId: 'post-1',
        actionId: 'approve',
        token: const RichAttachmentActionToken('encrypted-cookie'),
        selectedOption: 'yes',
      );

      expect(api.postId, 'post-1');
      expect(api.actionId, 'approve');
      expect(api.request?.cookie, 'encrypted-cookie');
      expect(api.request?.selectedOption, 'yes');
      expect(api.refreshedPostId, 'post-1');
      expect(result.updatedPost.message, 'Updated by integration');
      expect(result.gotoLocation, 'https://chat.example.com/team/pl/next');
    },
  );

  test(
    'dispatches a legacy action when the server did not include a cookie',
    () async {
      final _ActionApi api = _ActionApi();
      final MattermostPostActionRepository repository =
          MattermostPostActionRepository(
            api: api,
            messageMapper: const MattermostMessageMapper(),
            users: FakeUserRepository(),
          );

      await repository.execute(
        session: AuthSession(
          serverUrl: Uri.parse('https://chat.example.com'),
          userId: 'me',
          username: 'me',
        ),
        postId: 'post-1',
        actionId: 'approve',
        token: null,
      );

      expect(api.request?.cookie, isNull);
      expect(api.request?.toJson(), isEmpty);
    },
  );

  test(
    'maps ephemeral and edited posts from the shared realtime stream',
    () async {
      final _Gateway gateway = _Gateway();
      final SessionRealtimeService realtime = SessionRealtimeService(
        gateway: gateway,
        credentialStore: const _Credentials(),
      );
      addTearDown(realtime.dispose);
      final MattermostPostActionRepository repository =
          MattermostPostActionRepository(
            api: _ActionApi(),
            messageMapper: const MattermostMessageMapper(),
            users: FakeUserRepository(),
            realtime: realtime,
          );
      final StreamIterator<PostActionRealtimeEvent> events = StreamIterator(
        repository.watchRealtime(
          session: AuthSession(
            serverUrl: Uri.parse('https://chat.example.com'),
            userId: 'me',
            username: 'me',
          ),
        ),
      );
      addTearDown(events.cancel);
      final Future<bool> first = events.moveNext();
      await _waitUntil(() => gateway.started);

      gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'ephemeral_message',
            sequence: 1,
            data: <String, Object?>{
              'post': jsonEncode(<String, Object?>{
                'id': 'ephemeral',
                'channel_id': 'channel-1',
                'root_id': 'post-1',
                'user_id': 'me',
                'message': 'Approved',
              }),
            },
            broadcast: const <String, Object?>{'channel_id': 'channel-1'},
          ),
        ),
      );
      expect(await first, isTrue);
      expect(
        events.current,
        isA<PostActionEphemeralFeedback>()
            .having((value) => value.sourceRootPostId, 'root', 'post-1')
            .having((value) => value.message, 'message', 'Approved'),
      );

      final Future<bool> second = events.moveNext();
      gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'post_edited',
            sequence: 2,
            data: <String, Object?>{
              'post': jsonEncode(<String, Object?>{
                'id': 'post-1',
                'channel_id': 'channel-1',
                'user_id': 'ada',
                'message': 'Realtime edit',
                'create_at': 1,
              }),
            },
            broadcast: const <String, Object?>{'channel_id': 'channel-1'},
          ),
        ),
      );
      expect(await second, isTrue);
      expect(
        events.current,
        isA<PostActionPostUpdated>().having(
          (value) => value.post.message,
          'message',
          'Realtime edit',
        ),
      );
    },
  );
}

final class _ActionApi extends Fake implements MattermostApi {
  String? postId;
  String? actionId;
  String? refreshedPostId;
  MattermostPostActionRequestDto? request;

  @override
  Future<MattermostPostActionResponseDto> executePostAction({
    required String postId,
    required String actionId,
    required MattermostPostActionRequestDto request,
  }) async {
    this.postId = postId;
    this.actionId = actionId;
    this.request = request;
    return const MattermostPostActionResponseDto(
      status: 'OK',
      gotoLocation: 'https://chat.example.com/team/pl/next',
    );
  }

  @override
  Future<MattermostPostDto> getPost(String postId) async {
    refreshedPostId = postId;
    return const MattermostPostDto(
      id: 'post-1',
      userId: 'ada',
      channelId: 'channel-1',
      message: 'Updated by integration',
      createAt: 1,
    );
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached');
}

final class _Gateway implements WebSocketGateway {
  final StreamController<WebSocketGatewaySignal> _controller =
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
      (serverUrl: Uri.parse('https://chat.example.com'), token: 'secret');

  @override
  Future<void> save({required Uri serverUrl, required String token}) async {}
}
