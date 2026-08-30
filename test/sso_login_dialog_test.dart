import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/app/di/app_providers.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_repository.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/auth/domain/sso_provider.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/sso_login_dialog.dart';

void main() {
  testWidgets(
    'shows server-provided SSO methods on compact layout at large text',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_AuthRepository()),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SsoLoginDialog(),
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('sso-server-url')),
        'https://chat.example.com',
      );
      await tester.ensureVisible(find.text('Продолжить'));
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();

      expect(find.text('Company SAML'), findsOneWidget);
      expect(find.text('OpenID for everyone'), findsOneWidget);
      expect(find.text('Войти по токену'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('accepts a token after selecting token login', (
    WidgetTester tester,
  ) async {
    final _AuthRepository repository = _AuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: SsoLoginDialog()),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('sso-server-url')),
      'https://chat.example.com',
    );
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Войти по токену'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('mattermost-access-token')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('mattermost-access-token')),
      'personal-access-token',
    );
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();

    expect(repository.token, 'personal-access-token');
  });
}

final class _AuthRepository implements AuthRepository {
  String? token;

  @override
  Future<AuthSession> authenticateWithSessionToken({
    required Uri serverUrl,
    required String token,
  }) async {
    this.token = token;
    return AuthSession(serverUrl: serverUrl, userId: 'user-1', username: 'ada');
  }

  @override
  Future<AuthSession> authenticateWithSso({
    required Uri serverUrl,
    required SsoProvider provider,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelSsoAuthentication() async {}

  @override
  Future<List<SsoOption>> discoverSsoOptions({required Uri serverUrl}) async =>
      const <SsoOption>[
        SsoOption(provider: SsoProvider.saml, displayLabel: 'Company SAML'),
        SsoOption(
          provider: SsoProvider.openId,
          displayLabel: 'OpenID for everyone',
        ),
      ];

  @override
  Future<AuthSession?> restoreSession() async => null;

  @override
  Future<void> signOut() async {}
}
