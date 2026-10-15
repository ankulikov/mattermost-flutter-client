import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/authentication_methods.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';
import 'package:mattermost_flutter/src/domain/repositories/auth_repository.dart';
import 'package:mattermost_flutter/src/ui/auth/auth_strings.dart';
import 'package:mattermost_flutter/src/ui/auth/widgets/sso_login_dialog.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  testWidgets('explains why an HTTP public server address is rejected', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_AuthRepository()),
        ],
        child: const MaterialApp(home: SsoLoginDialog()),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('sso-server-url')),
      'http://chat.example.com',
    );
    await tester.tap(find.text(AuthStrings.continueLabel));
    await tester.pumpAndSettle();

    expect(find.text(AuthStrings.insecureProtocol), findsOneWidget);
  });

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

  testWidgets('shows and submits password login when supported', (
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
    await tester.tap(find.text('Войти по логину и паролю'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('mattermost-login-id')),
      'ada',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('mattermost-password')),
      'secret-password',
    );
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();

    expect(repository.loginId, 'ada');
    expect(repository.password, 'secret-password');
  });
}

final class _AuthRepository implements AuthRepository {
  String? token;
  String? loginId;
  String? password;

  @override
  Future<AuthSession> authenticateWithPassword({
    required Uri serverUrl,
    required String loginId,
    required String password,
  }) async {
    this.loginId = loginId;
    this.password = password;
    return AuthSession(serverUrl: serverUrl, userId: 'user-1', username: 'ada');
  }

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
  Future<AuthenticationMethods> discoverAuthenticationMethods({
    required Uri serverUrl,
  }) async => AuthenticationMethods(
    ssoOptions: await discoverSsoOptions(serverUrl: serverUrl),
    passwordLoginEnabled: true,
  );

  @override
  Future<AuthSession?> restoreSession() async => null;

  @override
  Future<void> signOut() async {}
}
