import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dio_mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';

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
}

final class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      '{"order":[],"posts":{},"next_post_id":"",'
      '"prev_post_id":"","has_next":false}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
