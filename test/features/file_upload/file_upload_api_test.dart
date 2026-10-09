import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/debug_http_logging_interceptor.dart';
import 'package:mattermost_flutter/src/data/api/dio_mattermost_api.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';

void main() {
  test('uploads one multipart file and accepts its server ID', () async {
    final adapter = _Adapter(
      '{"file_infos":[{"id":"file-id","name":"private.txt"}]}',
    );
    final logs = <String>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter
      ..interceptors.add(DebugHttpLoggingInterceptor(logWriter: logs.add));
    final id = await DioMattermostApi(dio: dio).uploadFile(
      channelId: 'channel-id',
      name: 'private.txt',
      length: 4,
      stream: Stream<Uint8List>.value(Uint8List.fromList(utf8.encode('data'))),
      onProgress: (_, _) {},
    );
    expect(id, 'file-id');
    expect(adapter.options?.path, '/files');
    expect(adapter.options?.contentType, contains('multipart/form-data'));
    final body = latin1.decode(adapter.requestBytes);
    expect(body, contains('name="channel_id"'));
    expect(body, contains('channel-id'));
    expect(body, contains('name="files"'));
    expect(body, contains('filename="private.txt"'));
    expect(logs.join(), isNot(contains('private.txt')));
    expect(logs.join(), isNot(contains('file-id')));
  });

  test('rejects malformed upload response', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = _Adapter('{"file_infos":[]}');
    await expectLater(
      DioMattermostApi(dio: dio).uploadFile(
        channelId: 'channel',
        name: 'file',
        length: 1,
        stream: Stream<Uint8List>.value(Uint8List.fromList(<int>[1])),
        onProgress: (_, _) {},
      ),
      throwsFormatException,
    );
  });

  test('post JSON includes ordered files and thread root', () {
    final dto = MattermostCreatePostRequestDto(
      channelId: 'channel',
      message: '',
      pendingPostId: 'pending',
      rootId: 'root',
      fileIds: <String>['first', 'second'],
    );
    expect(dto.toJson()['file_ids'], <String>['first', 'second']);
    expect(dto.toJson()['root_id'], 'root');
    expect(dto.toJson()['message'], '');
  });
}

final class _Adapter implements HttpClientAdapter {
  _Adapter(this.response);
  final String response;
  RequestOptions? options;
  List<int> requestBytes = <int>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    this.options = options;
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        requestBytes.addAll(chunk);
      }
    }
    return ResponseBody.fromString(
      response,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
