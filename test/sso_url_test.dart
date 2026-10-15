import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';
import 'package:mattermost_flutter/src/domain/policies/sso_url.dart';

void main() {
  group('tryNormalizeMattermostServerUrl', () {
    test('normalizes a root deployment and removes its trailing slash', () {
      expect(
        tryNormalizeMattermostServerUrl('  https://chat.example.com/  '),
        Uri.parse('https://chat.example.com'),
      );
    });

    test('preserves a Mattermost deployment path prefix', () {
      expect(
        tryNormalizeMattermostServerUrl('https://chat.example.com/mattermost/'),
        Uri.parse('https://chat.example.com/mattermost'),
      );
    });

    test('preserves explicit HTTP origins for allowed hosts', () {
      expect(
        tryNormalizeMattermostServerUrl('http://localhost:8065/mattermost'),
        Uri.parse('http://localhost:8065/mattermost'),
      );
      expect(
        tryNormalizeMattermostServerUrl('http://127.0.0.1:8065'),
        Uri.parse('http://127.0.0.1:8065'),
      );
    });

    test(
      'rejects credentials, query parameters, fragments, and unsafe URLs',
      () {
        for (final String value in <String>[
          'https://user:password@chat.example.com',
          'https://chat.example.com/?next=/login',
          'https://chat.example.com/#section',
          'ftp://chat.example.com',
          'http://chat.example.com',
          'https://',
        ]) {
          expect(tryNormalizeMattermostServerUrl(value), isNull, reason: value);
        }
      },
    );
  });

  group('buildSsoLoginUrl', () {
    test('creates the SAML mobile URL for a root deployment', () {
      expect(
        buildSsoLoginUrl(
          serverUrl: Uri.parse('https://chat.example.com'),
          provider: SsoProvider.saml,
        ),
        Uri.parse('https://chat.example.com/login/sso/saml?action=mobile'),
      );
    });

    test(
      'creates the OpenID mobile URL without losing a deployment prefix',
      () {
        expect(
          buildSsoLoginUrl(
            serverUrl: Uri.parse('https://chat.example.com/mattermost/'),
            provider: SsoProvider.openId,
          ),
          Uri.parse(
            'https://chat.example.com/mattermost/oauth/openid/mobile_login',
          ),
        );
      },
    );
  });
}
