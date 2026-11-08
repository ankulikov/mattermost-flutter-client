import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

typedef MattermostStatusLogWriter = void Function(String message);

/// Emits status-only Mattermost HTTP diagnostics in debug and release builds.
///
/// Flutter's [debugPrint] writes to Android logcat. URL queries, fragments,
/// and embedded credentials are removed before a line reaches the log sink.
final class MattermostStatusLoggingInterceptor extends Interceptor {
  MattermostStatusLoggingInterceptor({MattermostStatusLogWriter? logWriter})
    : _logWriter = logWriter ?? debugPrint;

  final MattermostStatusLogWriter _logWriter;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _logStatus(err.response?.statusCode, err.requestOptions);
    handler.next(err);
  }

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    _logStatus(response.statusCode, response.requestOptions);
    handler.next(response);
  }

  void _logStatus(int? status, RequestOptions request) {
    if (status != 401 &&
        status != 403 &&
        (status == null || status < 500 || status > 599)) {
      return;
    }
    _logWriter(
      'Mattermost response: $status ${_safeMethod(request.method)} '
      '${_safeUrl(request.uri)}',
    );
  }

  static String _safeMethod(String method) => switch (method.toUpperCase()) {
    'GET' => 'GET',
    'POST' => 'POST',
    'PUT' => 'PUT',
    'PATCH' => 'PATCH',
    'DELETE' => 'DELETE',
    _ => 'OTHER',
  };

  static String _safeUrl(Uri uri) {
    if ((uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      return 'unknown-origin';
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
  }
}
