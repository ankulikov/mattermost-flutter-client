import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

typedef AuthLogWriter = void Function(String message);

/// Writes structured, secret-free authentication diagnostics in debug builds.
///
/// Callers must pass only metadata. URLs are reduced to origin/path plus query
/// key names, and exception messages are intentionally never accepted.
final class AuthDiagnostics {
  AuthDiagnostics({AuthLogWriter? logWriter})
    : _logWriter = logWriter ?? _writeToDeveloperLog;

  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  final AuthLogWriter _logWriter;

  void event(String event, [Map<String, Object?> fields = const {}]) {
    if (!kDebugMode) return;
    _logWriter(_encoder.convert(<String, Object?>{'event': event, ...fields}));
  }

  /// Keeps routing information useful for SSO debugging without retaining any
  /// query or fragment values (which may contain codes, state, or tokens).
  static Map<String, Object?> safeUri(Uri? uri) {
    if (uri == null) {
      return const <String, Object?>{'present': false};
    }
    final List<String> queryKeys = uri.queryParametersAll.keys.toList()..sort();
    return <String, Object?>{
      'present': true,
      'scheme': uri.scheme.toLowerCase(),
      'host': uri.host.toLowerCase(),
      if (uri.hasPort) 'port': uri.port,
      'path': uri.path.isEmpty ? '/' : uri.path,
      if (queryKeys.isNotEmpty) 'query_keys': queryKeys,
      'has_fragment': uri.hasFragment,
      'has_user_info': uri.userInfo.isNotEmpty,
    };
  }

  static void _writeToDeveloperLog(String message) {
    developer.log(message, name: 'MattermostAuth', level: 500);
  }
}
