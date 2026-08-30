import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mattermost_flutter/src/data/api/debug_http_logging_interceptor.dart';
import 'package:mattermost_flutter/src/data/api/dio_mattermost_api.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';

abstract interface class MattermostApiClientFactory {
  MattermostApiClient create({required Uri serverUrl, required String token});
}

abstract interface class MattermostApiClient {
  MattermostApi get api;

  void close();
}

final class MattermostClientFactory implements MattermostApiClientFactory {
  const MattermostClientFactory();

  @override
  MattermostApiClient create({required Uri serverUrl, required String token}) {
    final String base = serverUrl.toString().replaceAll(RegExp(r'/$'), '');
    final Dio dio = Dio(
      BaseOptions(
        baseUrl: '$base/api/v4',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ),
    );
    if (kDebugMode) {
      dio.interceptors.add(DebugHttpLoggingInterceptor());
    }
    return DioMattermostApiClient(dio);
  }
}

final class DioMattermostApiClient implements MattermostApiClient {
  DioMattermostApiClient(this._dio) : api = DioMattermostApi(dio: _dio);

  final Dio _dio;

  @override
  final MattermostApi api;

  @override
  void close() => _dio.close(force: true);
}
