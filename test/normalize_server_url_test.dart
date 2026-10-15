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

  test('preserves an explicit HTTP scheme for an allowed host', () {
    expect(
      normalize('http://localhost:8065/mattermost/'),
      Uri.parse('http://localhost:8065/mattermost'),
    );
  });

  test('uses only HTTPS for a schemeless remote address', () {
    expect(normalize.candidates('chat.example.com/mattermost/'), <Uri>[
      Uri.parse('https://chat.example.com/mattermost'),
    ]);
  });

  for (final String host in <String>[
    'localhost:8065',
    '10.1.2.3',
    '172.16.0.1',
    '172.31.255.255',
    '192.168.1.1',
    '127.0.0.1:8065',
    '169.254.1.1',
    '100.64.0.1',
    '100.127.255.255',
    '[fc00::1]',
    '[fdff::1]',
    'mattermost.lan',
    'mattermost.local',
  ]) {
    test('falls back to HTTP for an allowed schemeless host: $host', () {
      final List<Uri> candidates = normalize.candidates(host);
      expect(candidates.map((Uri uri) => uri.scheme), <String>[
        'https',
        'http',
      ]);
    });
  }

  for (final String value in <String>[
    'http://chat.example.com',
    'http://192.168.attacker.com',
    'http://172.15.0.1',
    'http://172.32.0.1',
    'http://100.63.0.1',
    'http://100.128.0.1',
    'http://[::1]',
  ]) {
    test('rejects HTTP for a host outside allowed ranges: $value', () {
      expect(
        () => normalize(value),
        throwsA(
          isA<AuthFailure>().having(
            (AuthFailure failure) => failure.kind,
            'kind',
            AuthFailureKind.insecureProtocol,
          ),
        ),
      );
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
