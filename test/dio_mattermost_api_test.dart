import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dio_mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';

void main() {
  test('loads a fresh complete user profile by id', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '{"id":"ada","username":"ada","position":"Engineer",'
          '"email":"ada@example.com"}',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    final MattermostUserDto user = await api.getUserById('ada');

    expect(adapter.request?.method, 'GET');
    expect(adapter.request?.path, '/users/ada');
    expect(user.position, 'Engineer');
    expect(user.email, 'ada@example.com');
  });

  test('loads user status by id', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body: '{"user_id":"ada","status":"online","manual":false}',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    final MattermostUserStatusDto status = await api.getUserStatus('ada');

    expect(adapter.request?.path, '/users/ada/status');
    expect(status.userId, 'ada');
    expect(status.status, 'online');
  });

  test('creates a direct channel for exactly two users', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '{"id":"dm-1","team_id":"","type":"D",'
          '"display_name":"","name":"ada__me"}',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    final MattermostChannelDto channel = await api.createDirectChannel(
      currentUserId: 'me',
      otherUserId: 'ada',
    );

    expect(adapter.request?.method, 'POST');
    expect(adapter.request?.path, '/channels/direct');
    expect(adapter.request?.data, '["me","ada"]');
    expect(channel.id, 'dm-1');
  });

  test('creates a text post with reply and pending identifiers', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '{"id":"post-1","user_id":"me","channel_id":"channel-1",'
          '"root_id":"root-1","message":"Hello","pending_post_id":"pending-1"}',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    final MattermostPostDto created = await api.createPost(
      const MattermostCreatePostRequestDto(
        channelId: 'channel-1',
        message: 'Hello',
        rootId: 'root-1',
        pendingPostId: 'pending-1',
      ),
    );

    expect(adapter.request?.method, 'POST');
    expect(adapter.request?.path, '/posts');
    expect(adapter.request?.data, <String, Object?>{
      'channel_id': 'channel-1',
      'message': 'Hello',
      'pending_post_id': 'pending-1',
      'root_id': 'root-1',
    });
    expect(created.id, 'post-1');
    expect(created.rootId, 'root-1');
  });

  test('downloads a versioned authenticated profile image as bytes', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      contentType: 'image/png',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    final MattermostImageDto image = await api.getUserProfileImage(
      userId: 'user-1',
      lastPictureUpdate: 1234,
    );

    expect(adapter.request?.path, '/users/user-1/image');
    expect(adapter.request?.queryParameters, <String, Object?>{'_': 1234});
    expect(adapter.request?.headers['Accept'], 'image/*');
    expect(adapter.request?.responseType, ResponseType.bytes);
    expect(image.bytes, <int>[1, 2, 3]);
    expect(image.contentType, 'image/png');
  });

  test('resolves custom emoji metadata by encoded name', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '{"id":"emoji-1","creator_id":"ada","name":"party+parrot",'
          '"create_at":1,"update_at":2,"delete_at":0}',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;

    final MattermostEmojiDto emoji = await DioMattermostApi(
      dio: dio,
    ).getCustomEmojiByName('party+parrot');

    expect(adapter.request?.method, 'GET');
    expect(adapter.request?.path, '/emoji/name/party%2Bparrot');
    expect(emoji.id, 'emoji-1');
  });

  test('downloads an authenticated custom emoji image', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      bytes: Uint8List.fromList(<int>[4, 5, 6]),
      contentType: 'image/gif',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;

    final MattermostImageDto image = await DioMattermostApi(
      dio: dio,
    ).getCustomEmojiImage('emoji-1');

    expect(adapter.request?.path, '/emoji/emoji-1/image');
    expect(adapter.request?.headers['Accept'], 'image/*');
    expect(adapter.request?.responseType, ResponseType.bytes);
    expect(image.bytes, <int>[4, 5, 6]);
    expect(image.contentType, 'image/gif');
  });

  test('sends the complete cursor for upward thread pagination', () async {
    final _RecordingAdapter adapter = _RecordingAdapter();
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    await api.getPostThread(
      rootPostId: 'root-1',
      perPage: 60,
      fromPost: 'reply-59',
      fromCreateAt: 2059,
      direction: PostThreadDirection.up,
    );

    expect(adapter.request?.path, '/posts/root-1/thread');
    expect(adapter.request?.queryParameters, <String, Object?>{
      'perPage': 60,
      'direction': 'up',
      'fromPost': 'reply-59',
      'fromCreateAt': 2059,
    });
  });

  test('requests an extended followed-threads page with a cursor', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '{"total":0,"total_unread_threads":0,'
          '"total_unread_mentions":0,"threads":[]}',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    await api.getUserThreads(
      userId: 'me',
      teamId: 'team-1',
      before: 'root-200',
    );

    expect(adapter.request?.path, '/users/me/teams/team-1/threads');
    expect(adapter.request?.queryParameters, <String, Object?>{
      'per_page': 60,
      'extended': true,
      'before': 'root-200',
    });
  });

  test('marks a followed thread read at the supplied timestamp', () async {
    final _RecordingAdapter adapter = _RecordingAdapter();
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    await api.updateThreadRead(
      userId: 'me',
      teamId: 'team-1',
      threadId: 'root-1',
      timestamp: 123456,
    );

    expect(adapter.request?.method, 'PUT');
    expect(
      adapter.request?.path,
      '/users/me/teams/team-1/threads/root-1/read/123456',
    );
  });

  test(
    'cancels an in-flight Dio request from its presentation scope',
    () async {
      final _CancellableAdapter adapter = _CancellableAdapter();
      final Dio dio = Dio(
        BaseOptions(baseUrl: 'https://chat.example.com/api/v4'),
      )..httpClientAdapter = adapter;
      final DioMattermostApi api = DioMattermostApi(dio: dio);
      final RequestCancellation cancellation = RequestCancellation();

      final Future<MattermostUserDto> request = cancellation.run(
        api.getCurrentUser,
      );
      await adapter.started.future;
      cancellation.cancel('screen disposed');

      await expectLater(
        request,
        throwsA(
          isA<DioException>().having(
            (DioException error) => error.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      expect(adapter.cancelled, isTrue);
    },
  );
}

final class _CancellableAdapter implements HttpClientAdapter {
  final Completer<void> started = Completer<void>();
  bool cancelled = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    started.complete();
    await cancelFuture;
    cancelled = true;
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

final class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({
    this.body =
        '{"order":[],"posts":{},"next_post_id":"",'
        '"prev_post_id":"","has_next":false}',
    this.bytes,
    this.contentType = 'application/json',
  });

  final String body;
  final Uint8List? bytes;
  final String contentType;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody(
      bytes == null
          ? Stream<Uint8List>.value(Uint8List.fromList(body.codeUnits))
          : Stream<Uint8List>.value(bytes!),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
