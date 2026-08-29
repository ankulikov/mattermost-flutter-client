import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/auth/data/sso_browser_policy.dart';
import 'package:mattermost_flutter/src/features/auth/domain/sso_provider.dart';

void main() {
  group('SSO start URL', () {
    test('preserves a Mattermost subpath for SAML', () {
      final Uri url = SsoBrowserPolicy.startUrl(
        serverUrl: Uri.parse('https://chat.example.com/mattermost'),
        provider: SsoProvider.saml,
      );

      expect(
        url,
        Uri.parse(
          'https://chat.example.com/mattermost/login/sso/saml?action=mobile',
        ),
      );
    });

    test('builds the OpenID mobile endpoint at the server root', () {
      expect(
        SsoBrowserPolicy.startUrl(
          serverUrl: Uri.parse('https://chat.example.com/'),
          provider: SsoProvider.openId,
        ),
        Uri.parse('https://chat.example.com/oauth/openid/mobile_login'),
      );
    });
  });

  group('navigation policy', () {
    test('accepts only http(s) browser navigations without user info', () {
      expect(
        SsoBrowserPolicy.isAllowedNavigation(Uri.parse('https://idp.example')),
        isTrue,
      );
      expect(
        SsoBrowserPolicy.isAllowedNavigation(Uri.parse('http://idp.example')),
        isFalse,
      );
      expect(
        SsoBrowserPolicy.isAllowedNavigation(
          Uri.parse('http://localhost:8080'),
        ),
        isTrue,
      );
      expect(
        SsoBrowserPolicy.isAllowedNavigation(Uri.parse('file:///etc/passwd')),
        isFalse,
      );
      expect(
        SsoBrowserPolicy.isAllowedNavigation(Uri.parse('javascript:alert(1)')),
        isFalse,
      );
      expect(
        SsoBrowserPolicy.isAllowedNavigation(Uri.parse('data:text/html,hello')),
        isFalse,
      );
      expect(
        SsoBrowserPolicy.isAllowedNavigation(
          Uri.parse('https://a@idp.example'),
        ),
        isFalse,
      );
    });

    test(
      'requires exact origin and deployment path before reading cookies',
      () {
        final Uri serverUrl = Uri.parse('https://chat.example.com/mattermost');

        expect(
          SsoBrowserPolicy.isExpectedReturn(
            serverUrl: serverUrl,
            navigationUrl: Uri.parse(
              'https://chat.example.com/mattermost/channels/town-square',
            ),
          ),
          isTrue,
        );
        expect(
          SsoBrowserPolicy.isExpectedReturn(
            serverUrl: serverUrl,
            navigationUrl: Uri.parse('https://chat.example.com/other'),
          ),
          isFalse,
        );
        expect(
          SsoBrowserPolicy.isExpectedReturn(
            serverUrl: serverUrl,
            navigationUrl: Uri.parse('https://evil.example/mattermost'),
          ),
          isFalse,
        );
        expect(
          SsoBrowserPolicy.isExpectedReturn(
            serverUrl: serverUrl,
            navigationUrl: Uri.parse('http://chat.example.com/mattermost'),
          ),
          isFalse,
        );
      },
    );
  });

  group('cookie extraction policy', () {
    final Uri serverUrl = Uri(scheme: 'https', host: 'chat.example.com');

    test('extracts only an exact non-empty MMAUTHTOKEN cookie', () {
      expect(
        SsoBrowserPolicy.sessionTokenFromCookies(
          serverUrl: serverUrl,
          cookies: const <SsoBrowserCookie>[
            SsoBrowserCookie(name: 'MMAUTHTOKEN_OLD', value: 'wrong'),
            SsoBrowserCookie(name: 'MMAUTHTOKEN', value: 'session-token'),
          ],
        ),
        'session-token',
      );
    });

    test('rejects empty, oversized, and foreign-domain token cookies', () {
      expect(
        SsoBrowserPolicy.sessionTokenFromCookies(
          serverUrl: serverUrl,
          cookies: const <SsoBrowserCookie>[
            SsoBrowserCookie(name: 'MMAUTHTOKEN', value: ''),
          ],
        ),
        isNull,
      );
      expect(
        SsoBrowserPolicy.sessionTokenFromCookies(
          serverUrl: serverUrl,
          cookies: const <SsoBrowserCookie>[
            SsoBrowserCookie(name: 'MMAUTHTOKEN', value: '   '),
          ],
        ),
        isNull,
      );
      expect(
        SsoBrowserPolicy.sessionTokenFromCookies(
          serverUrl: serverUrl,
          cookies: <SsoBrowserCookie>[
            SsoBrowserCookie(
              name: 'MMAUTHTOKEN',
              value: 'a' * (SsoBrowserPolicy.maxSessionTokenLength + 1),
            ),
          ],
        ),
        isNull,
      );
      expect(
        SsoBrowserPolicy.sessionTokenFromCookies(
          serverUrl: serverUrl,
          cookies: const <SsoBrowserCookie>[
            SsoBrowserCookie(
              name: 'MMAUTHTOKEN',
              value: 'foreign',
              domain: 'other.example',
            ),
          ],
        ),
        isNull,
      );
    });
  });
}
