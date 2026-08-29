import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_server_discovery.dart';

void main() {
  test('loads the legacy client config without authorization', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '{"EnableSaml":"true","SamlLoginButtonText":"Sign in with SAML",'
          '"EnableSignUpWithOpenId":true,"OpenIdButtonText":"OpenID"}',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostServerDiscoveryClient client =
        DioMattermostServerDiscoveryClient(dio);

    final config = await client.getClientConfig();

    expect(adapter.request?.method, 'GET');
    expect(adapter.request?.path, '/config/client');
    expect(adapter.request?.queryParameters, <String, String>{'format': 'old'});
    expect(adapter.request?.headers.containsKey('Authorization'), isFalse);
    expect(config.enableSaml, isTrue);
    expect(config.samlLoginButtonText, 'Sign in with SAML');
    expect(config.enableSignUpWithOpenId, isTrue);
    expect(config.openIdButtonText, 'OpenID');
  });

  test('rejects a non-object client config response', () async {
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = _RecordingAdapter(body: '[]');
    final DioMattermostServerDiscoveryClient client =
        DioMattermostServerDiscoveryClient(dio);

    await expectLater(client.getClientConfig(), throwsFormatException);
  });

  test(
    'keeps a Mattermost deployment path prefix in the API request',
    () async {
      final _RecordingAdapter adapter = _RecordingAdapter(body: '{}');
      final Dio dio = Dio(
        BaseOptions(baseUrl: 'https://chat.example.com/mattermost/api/v4'),
      )..httpClientAdapter = adapter;

      await DioMattermostServerDiscoveryClient(dio).getClientConfig();

      expect(
        adapter.request?.uri,
        Uri.parse(
          'https://chat.example.com/mattermost/api/v4/config/client?format=old',
        ),
      );
    },
  );
}

final class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({required this.body});

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
