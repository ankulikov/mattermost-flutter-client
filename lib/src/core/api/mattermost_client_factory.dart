import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mattermost_flutter/src/core/api/debug_http_logging_interceptor.dart';
import 'package:mattermost_flutter/src/core/api/dio_mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';

abstract interface class MattermostApiFactory {
  MattermostApi create({required Uri serverUrl, required String token});
}

final class MattermostClientFactory implements MattermostApiFactory {
  const MattermostClientFactory();

  @override
  MattermostApi create({required Uri serverUrl, required String token}) {
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
    return DioMattermostApi(dio: dio);
  }
}
