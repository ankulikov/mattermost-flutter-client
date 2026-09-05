import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mattermost_flutter/src/data/api/debug_http_logging_interceptor.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';

/// Factory for short-lived unauthenticated Mattermost discovery transports.
///
/// Discovery deliberately has its own client because it runs before any user
/// session exists and must never inherit an Authorization header.
abstract interface class MattermostServerDiscoveryClientFactory {
  MattermostServerDiscoveryClient create({required Uri serverUrl});
}

abstract interface class MattermostServerDiscoveryClient {
  Future<MattermostClientConfigDto> getClientConfig();

  /// Exchanges a password for a short-lived Mattermost session token.
  Future<String> login({required String loginId, required String password});

  void close();
}

/// An unavailable discovery endpoint without exposing Dio to feature code.
final class MattermostServerDiscoveryNetworkException implements Exception {
  const MattermostServerDiscoveryNetworkException();
}

enum MattermostServerLoginFailureKind { invalidCredentials, network }

final class MattermostServerLoginException implements Exception {
  const MattermostServerLoginException(this.kind);

  final MattermostServerLoginFailureKind kind;
}

final class DioMattermostServerDiscoveryClientFactory
    implements MattermostServerDiscoveryClientFactory {
  const DioMattermostServerDiscoveryClientFactory();

  @override
  MattermostServerDiscoveryClient create({required Uri serverUrl}) {
    final String serverBase = serverUrl.toString().replaceFirst(
      RegExp(r'/$'),
      '',
    );
    final Dio dio = Dio(
      BaseOptions(
        baseUrl: '$serverBase/api/v4',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: const <String, String>{'Accept': 'application/json'},
      ),
    );
    if (kDebugMode) {
      dio.interceptors.add(DebugHttpLoggingInterceptor());
    }
    return DioMattermostServerDiscoveryClient(dio);
  }
}

final class DioMattermostServerDiscoveryClient
    implements MattermostServerDiscoveryClient {
  DioMattermostServerDiscoveryClient(this._dio);

  final Dio _dio;

  @override
  Future<MattermostClientConfigDto> getClientConfig() async {
    try {
      final Response<Object?> response = await _dio.get<Object?>(
        '/config/client',
        queryParameters: const <String, String>{'format': 'old'},
      );
      return MattermostClientConfigDto.fromJson(_jsonObject(response.data));
    } on DioException {
      throw const MattermostServerDiscoveryNetworkException();
    }
  }

  @override
  Future<String> login({
    required String loginId,
    required String password,
  }) async {
    try {
      final Response<Object?> response = await _dio.post<Object?>(
        '/users/login',
        data: <String, String>{'login_id': loginId, 'password': password},
      );
      final String? token = response.headers.value('Token');
      if (token == null || token.isEmpty) {
        throw const FormatException('Missing session token in login response');
      }
      return token;
    } on DioException catch (error) {
      final int? status = error.response?.statusCode;
      if (status == 400 || status == 401 || status == 403) {
        throw const MattermostServerLoginException(
          MattermostServerLoginFailureKind.invalidCredentials,
        );
      }
      throw const MattermostServerLoginException(
        MattermostServerLoginFailureKind.network,
      );
    }
  }

  @override
  void close() => _dio.close(force: true);
}

JsonMap _jsonObject(Object? value) {
  if (value is! Map) {
    throw const FormatException('Expected object response for client config');
  }
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('Expected string key in client config');
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}
