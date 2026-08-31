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

  test('permits HTTP only for local development hosts', () {
    expect(
      normalize('http://localhost:8065/mattermost/'),
      Uri.parse('http://localhost:8065/mattermost'),
    );
  });

  for (final String value in <String>[
    'http://chat.example.com',
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
