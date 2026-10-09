import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

typedef HttpLogWriter = void Function(String message);

/// Logs sanitized HTTP request and response payloads in debug builds.
///
/// Authentication data, message contents, and common personal-data fields are
/// redacted before they reach the log sink.
final class DebugHttpLoggingInterceptor extends Interceptor {
  DebugHttpLoggingInterceptor({HttpLogWriter? logWriter})
    : _logWriter = logWriter ?? _writeToDeveloperLog;

  static const String _redacted = '<redacted>';
  static const String _omittedBinary = '<binary payload omitted>';
  static const String _omittedNonJson = '<non-JSON payload omitted>';
  static const int _maxLoggedListItems = 10;
  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  static final RegExp _mattermostId = RegExp(r'^[a-z0-9]{26}$');

  static const Set<String> _sensitiveKeys = <String>{
    'access_token',
    'auth_data',
    'authorization',
    'client_secret',
    'cookie',
    'email',
    // 'first_name',
    'last_name',
    'message',
    'metadata',
    'nickname',
    'passwd',
    'password',
    'phone',
    'phone_number',
    'props',
    'proxy-authorization',
    'refresh_token',
    'secret',
    'set-cookie',
    'token',
    'user_id',
    'username',
  };

  static const Set<String> _sensitiveQueryKeys = <String>{
    'client_data',
    'client_id',
    'email',
    'code',
    'execution',
    'iss',
    'q',
    'query',
    'redirect_uri',
    'relaystate',
    'samlresponse',
    'search',
    'session_code',
    'session_state',
    'state',
    'tab_id',
    'term',
    'token',
    'username',
  };

  final HttpLogWriter _logWriter;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode && err.response != null && !_isUpload(err.requestOptions)) {
      _logResponse(err.response!.data);
    }
    handler.next(err);
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      _log(<String, Object?>{
        'method': options.method,
        'url': _sanitizeUrl(options.uri),
        'payload': _isUpload(options)
            ? _omittedBinary
            : _normalizePayload(options.data),
      });
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    if (kDebugMode) {
      if (!_isUpload(response.requestOptions)) _logResponse(response.data);
    }
    handler.next(response);
  }

  void _log(Object? value) => _logWriter(_encoder.convert(value));

  void _logResponse(Object? data) =>
      _log(<String, Object?>{'payload': _normalizePayload(data)});

  static bool _isUpload(RequestOptions options) =>
      options.uri.path.endsWith('/api/v4/files');

  static Object? _normalizePayload(Object? value) {
    if (value is String) {
      try {
        return _sanitizeJsonValue(jsonDecode(value));
      } on FormatException {
        return _omittedNonJson;
      }
    }
    return _sanitizeJsonValue(value);
  }

  static Object? _sanitizeJsonValue(Object? value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is Map<Object?, Object?>) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in value.entries)
          entry.key.toString(): _isSensitiveKey(entry.key.toString())
              ? _redacted
              : _sanitizeJsonValue(entry.value),
      };
    }
    if (value is Iterable<Object?>) {
      return value
          .take(_maxLoggedListItems)
          .map<Object?>(_sanitizeJsonValue)
          .toList(growable: false);
    }
    if (value is FormData) {
      return <String, Object?>{
        for (final MapEntry<String, String> field in value.fields)
          field.key: _isSensitiveKey(field.key)
              ? _redacted
              : _sanitizeJsonValue(field.value),
        for (final MapEntry<String, MultipartFile> file in value.files)
          file.key: _omittedBinary,
      };
    }
    if (value is Uint8List || value is Stream<List<int>>) {
      return _omittedBinary;
    }
    return '<unsupported ${value.runtimeType} payload omitted>';
  }

  static bool _isSensitiveKey(String key) {
    final String normalized = key.toLowerCase();
    return _sensitiveKeys.contains(normalized) ||
        normalized.endsWith('_token') ||
        normalized.endsWith('_password') ||
        normalized.endsWith('_secret');
  }

  static String _sanitizeUrl(Uri uri) {
    final List<String> segments = <String>[];
    for (var index = 0; index < uri.pathSegments.length; index++) {
      final String segment = uri.pathSegments[index];
      final String? previous = index == 0 ? null : uri.pathSegments[index - 1];
      final bool followsPersonalLookup =
          previous == 'email' || previous == 'username';
      segments.add(
        _mattermostId.hasMatch(segment) || followsPersonalLookup
            ? _redacted
            : segment,
      );
    }

    final Map<String, String> query = <String, String>{
      for (final MapEntry<String, String> entry in uri.queryParameters.entries)
        entry.key: _sensitiveQueryKeys.contains(entry.key.toLowerCase())
            ? _redacted
            : entry.value,
    };
    return uri
        .replace(
          pathSegments: segments,
          queryParameters: query.isEmpty ? null : query,
        )
        .toString();
  }

  static void _writeToDeveloperLog(String message) {
    developer.log(message, name: 'MattermostHttp', level: 500);
  }
}
