import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_failure.dart';
import 'package:mattermost_flutter/src/domain/policies/normalize_server_url.dart';

void main() {
  const NormalizeServerUrl normalize = NormalizeServerUrl();

  test('normalizes root and Mattermost subpath URLs', () {
    expect(
      normalize('https://chat.example.com/'),
      Uri.parse('https://chat.example.com'),
    );
    expect(
      normalize('https://chat.example.com/mattermost///'),
      Uri.parse('https://chat.example.com/mattermost'),
    );
  });

  test('preserves an explicit HTTP scheme', () {
    expect(
      normalize('http://localhost:8065/mattermost/'),
      Uri.parse('http://localhost:8065/mattermost'),
    );
    expect(
      normalize('http://chat.example.com'),
      Uri.parse('http://chat.example.com'),
    );
  });

  test('uses HTTPS first for a schemeless remote address', () {
    expect(normalize.candidates('chat.example.com/mattermost/'), <Uri>[
      Uri.parse('https://chat.example.com/mattermost'),
      Uri.parse('http://chat.example.com/mattermost'),
    ]);
  });

  for (final String host in <String>[
    'localhost:8065',
    '127.0.0.1:8065',
    'mattermost.lan',
    'mattermost.local',
  ]) {
    test('uses HTTP first for schemeless local address: $host', () {
      final List<Uri> candidates = normalize.candidates(host);
      expect(candidates.first.scheme, 'http');
      expect(candidates.last.scheme, 'https');
    });
  }

  for (final String value in <String>[
    'https://user@chat.example.com',
    'https://chat.example.com/?next=/login',
    'https://chat.example.com/#login',
    'ftp://chat.example.com',
  ]) {
    test('rejects unsafe server URL: $value', () {
      expect(
        () => normalize(value),
        throwsA(
          isA<AuthFailure>().having(
            (AuthFailure failure) => failure.kind,
            'kind',
            AuthFailureKind.invalidServer,
          ),
        ),
      );
    });
  }
}
