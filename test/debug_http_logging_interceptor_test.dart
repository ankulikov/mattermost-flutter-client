import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/debug_http_logging_interceptor.dart';

void main() {
  test('logs request and response as formatted sanitized JSON', () async {
    final List<String> logs = <String>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = _JsonAdapter(
        statusCode: 200,
        body: <String, Object?>{
          'id': 'post-id',
          'message': 'private response message',
          'username': 'alex',
          'count': 1,
        },
      )
      ..interceptors.add(DebugHttpLoggingInterceptor(logWriter: logs.add));

    await dio.post<Object?>(
      '/users/ids',
      data: jsonEncode(<Object?>[
        <String, Object?>{
          'user_id': 'personal-id',
          'page': 2,
          'message': 'private request message',
        },
      ]),
    );

    expect(logs, hasLength(2));
    expect(logs.first, contains('"method": "POST"'));
    expect(
      logs.first,
      contains('"url": "https://chat.example.com/api/v4/users/ids"'),
    );
    expect(logs.first, contains('\n  "payload": [\n'));
    expect(logs.first, contains('"page": 2'));
    expect(logs.first, isNot(contains('personal-id')));
    expect(logs.first, isNot(contains('private request message')));
    expect(logs.last, contains('"count": 1'));
    expect(logs.last, isNot(contains('private response message')));
    expect(logs.last, isNot(contains('alex')));
  });

  test('logs payload returned with an HTTP error', () async {
    final List<String> logs = <String>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = _JsonAdapter(
        statusCode: 400,
        body: <String, Object?>{
          'status_code': 400,
          'message': 'private server error',
        },
      )
      ..interceptors.add(DebugHttpLoggingInterceptor(logWriter: logs.add));

    await expectLater(
      dio.get<Object?>('/users/me'),
      throwsA(isA<DioException>()),
    );

    expect(logs, hasLength(2));
    expect(logs.last, contains('"status_code": 400'));
    expect(logs.last, isNot(contains('private server error')));
  });

  test('logs only the first ten items of every payload list', () async {
    final List<String> logs = <String>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = _JsonAdapter(
        statusCode: 200,
        body: <String, Object?>{
          'items': List<String>.generate(12, (int index) => 'response-$index'),
        },
      )
      ..interceptors.add(DebugHttpLoggingInterceptor(logWriter: logs.add));

    await dio.post<Object?>(
      '/items',
      data: <String, Object?>{
        'items': List<String>.generate(12, (int index) => 'request-$index'),
      },
    );

    expect(logs.first, contains('request-9'));
    expect(logs.first, isNot(contains('request-10')));
    expect(logs.last, contains('response-9'));
    expect(logs.last, isNot(contains('response-10')));
  });
}

final class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter({required this.statusCode, required this.body});

  final Object? body;
  final int statusCode;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }
}
