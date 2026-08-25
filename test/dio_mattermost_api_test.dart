import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dio_mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';

void main() {
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
  });

  final String body;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      body,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
