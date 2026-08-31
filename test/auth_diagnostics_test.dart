import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/logging/auth_diagnostics.dart';

void main() {
  test('logs SSO URL routing metadata without query or fragment values', () {
    final List<String> logs = <String>[];
    final AuthDiagnostics diagnostics = AuthDiagnostics(logWriter: logs.add);
    final Uri callback = Uri.parse(
      'https://chat.example.com/signup/openid/complete'
      '?state=csrf-secret&code=authorization-secret#private-fragment',
    );

    diagnostics.event('navigation', <String, Object?>{
      'url': AuthDiagnostics.safeUri(callback),
    });

    final Map<String, Object?> payload =
        jsonDecode(logs.single) as Map<String, Object?>;
    final Map<String, Object?> url = payload['url']! as Map<String, Object?>;
    expect(url['scheme'], 'https');
    expect(url['host'], 'chat.example.com');
    expect(url['path'], '/signup/openid/complete');
    expect(url['query_keys'], <Object?>['code', 'state']);
    expect(url['has_fragment'], isTrue);
    expect(logs.single, isNot(contains('csrf-secret')));
    expect(logs.single, isNot(contains('authorization-secret')));
    expect(logs.single, isNot(contains('private-fragment')));
  });

  test('does not expose custom-scheme session values', () {
    final Map<String, Object?> url = AuthDiagnostics.safeUri(
      Uri.parse(
        'mmauth://callback?MMAUTHTOKEN=session-secret&MMCSRF=csrf-secret',
      ),
    );
    final String encoded = jsonEncode(url);

    expect(url['scheme'], 'mmauth');
    expect(url['host'], 'callback');
    expect(url['query_keys'], <Object?>['MMAUTHTOKEN', 'MMCSRF']);
    expect(encoded, isNot(contains('session-secret')));
    expect(encoded, isNot(contains('csrf-secret')));
  });
}
