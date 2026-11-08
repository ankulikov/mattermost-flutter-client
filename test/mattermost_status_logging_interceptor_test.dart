import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_server_discovery.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_status_logging_interceptor.dart';

void main() {
  test('logs 401, 403, and 5xx responses with full paths', () async {
    final List<String> logs = <String>[];
    final _StatusAdapter adapter = _StatusAdapter();
    final Dio dio = _client(adapter: adapter, logs: logs);

    for (final int status in <int>[401, 403, 500, 503, 599]) {
      adapter.statusCode = status;
      await expectLater(
        dio.get<Object?>(
          '/users/private-user/teams/private-team/channels',
          queryParameters: const <String, String>{'token': 'query-secret'},
        ),
        throwsA(isA<DioException>()),
      );
    }

    expect(logs, <String>[
      for (final int status in <int>[401, 403, 500, 503, 599])
        'Mattermost response: $status GET '
            'https://chat.example.com/api/v4/users/private-user/teams/private-team/channels',
    ]);
    expect(logs.join(), contains('private-user'));
    expect(logs.join(), contains('private-team'));
    expect(logs.join(), isNot(contains('query-secret')));
    expect(logs.join(), isNot(contains('response-secret')));
    expect(logs.join(), contains('chat.example.com'));
  });

  test('logs a 5xx response accepted by validateStatus only once', () async {
    final List<String> logs = <String>[];
    final _StatusAdapter adapter = _StatusAdapter()..statusCode = 503;
    final Dio dio = _client(adapter: adapter, logs: logs);

    final Response<Object?> response = await dio.get<Object?>(
      '/config/client',
      options: Options(validateStatus: (int? status) => status == 503),
    );

    expect(response.statusCode, 503);
    expect(logs, <String>[
      'Mattermost response: 503 GET https://chat.example.com/api/v4/config/client',
    ]);
  });

  test('keeps deployment path but omits URL credentials and query', () async {
    final List<String> logs = <String>[];
    final _StatusAdapter adapter = _StatusAdapter()..statusCode = 401;
    final Dio dio =
        Dio(
            BaseOptions(
              baseUrl:
                  'https://private-user:private-password@chat.example.com/tenant-secret/api/v4',
            ),
          )
          ..httpClientAdapter = adapter
          ..interceptors.add(
            MattermostStatusLoggingInterceptor(logWriter: logs.add),
          );

    await expectLater(
      dio.get<Object?>(
        '/users/private-user',
        queryParameters: const <String, String>{'token': 'query-secret'},
      ),
      throwsA(isA<DioException>()),
    );

    expect(logs, <String>[
      'Mattermost response: 401 GET '
          'https://chat.example.com/tenant-secret/api/v4/users/private-user',
    ]);
    expect(logs.single, isNot(contains('private-password')));
    expect(logs.single, contains('tenant-secret'));
    expect(logs.single, isNot(contains('query-secret')));
  });

  test(
    'ignores successful, rate-limited, and transport-failed requests',
    () async {
      final List<String> logs = <String>[];
      final _StatusAdapter adapter = _StatusAdapter();
      final Dio dio = _client(adapter: adapter, logs: logs);

      adapter.statusCode = 200;
      await dio.get<Object?>('/users/me');
      adapter.statusCode = 429;
      await expectLater(
        dio.get<Object?>('/users/me'),
        throwsA(isA<DioException>()),
      );
      adapter.failTransport = true;
      await expectLater(
        dio.get<Object?>('/users/me'),
        throwsA(isA<DioException>()),
      );

      expect(logs, isEmpty);
    },
  );

  test('both production Mattermost clients emit status diagnostics', () async {
    final List<String> logs = <String>[];
    final DebugPrintCallback previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = previousDebugPrint);

    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    server.listen((HttpRequest request) async {
      request.response.statusCode = request.uri.path.endsWith('/users/me')
          ? 401
          : 503;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{}');
      await request.response.close();
    });
    final Uri serverUrl = Uri.parse('http://127.0.0.1:${server.port}');

    final MattermostApiClient authenticated = const MattermostClientFactory()
        .create(serverUrl: serverUrl, token: 'never-log-this-token');
    addTearDown(authenticated.close);
    await expectLater(
      authenticated.api.getCurrentUser(),
      throwsA(isA<DioException>()),
    );

    final MattermostServerDiscoveryClient discovery =
        const DioMattermostServerDiscoveryClientFactory().create(
          serverUrl: serverUrl,
        );
    addTearDown(discovery.close);
    await expectLater(
      discovery.getClientConfig(),
      throwsA(isA<MattermostServerDiscoveryNetworkException>()),
    );

    final List<String> statusLogs = logs
        .where((String line) => line.startsWith('Mattermost response: '))
        .toList(growable: false);
    expect(statusLogs, <String>[
      'Mattermost response: 401 GET ${serverUrl.origin}/api/v4/users/me',
      'Mattermost response: 503 GET ${serverUrl.origin}/api/v4/config/client',
    ]);
    expect(statusLogs.join(), isNot(contains('never-log-this-token')));
  });
}

Dio _client({required _StatusAdapter adapter, required List<String> logs}) =>
    Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter
      ..interceptors.add(
        MattermostStatusLoggingInterceptor(logWriter: logs.add),
      );

final class _StatusAdapter implements HttpClientAdapter {
  int statusCode = 200;
  bool failTransport = false;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (failTransport) throw StateError('Transport unavailable');
    return ResponseBody.fromString(
      jsonEncode(const <String, String>{'message': 'response-secret'}),
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }
}
