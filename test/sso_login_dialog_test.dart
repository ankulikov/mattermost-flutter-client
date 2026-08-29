import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/app/di/app_providers.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_repository.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/auth/domain/server_sso_discovery.dart';
import 'package:mattermost_flutter/src/features/auth/domain/sso_browser_gateway.dart';
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
            authRepositoryProvider.overrideWithValue(const _AuthRepository()),
            serverSsoDiscoveryProvider.overrideWithValue(const _Discovery()),
            ssoBrowserGatewayProvider.overrideWithValue(
              const _BrowserGateway(),
            ),
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
      expect(tester.takeException(), isNull);
    },
  );
}

final class _Discovery implements ServerSsoDiscovery {
  const _Discovery();

  @override
  Future<List<SsoOption>> discover(Uri serverUrl) async => const <SsoOption>[
    SsoOption(provider: SsoProvider.saml, displayLabel: 'Company SAML'),
    SsoOption(
      provider: SsoProvider.openId,
      displayLabel: 'OpenID for everyone',
    ),
  ];
}

final class _BrowserGateway implements SsoBrowserGateway {
  const _BrowserGateway();

  @override
  Future<SsoBrowserResult> authenticate({
    required Uri serverUrl,
    required SsoProvider provider,
  }) async => const SsoBrowserFailure(SsoBrowserFailureKind.cancelled);

  @override
  Future<void> cancel() async {}
}

final class _AuthRepository implements AuthRepository {
  const _AuthRepository();

  @override
  Future<AuthSession> authenticateWithSessionToken({
    required Uri serverUrl,
    required String token,
  }) => throw UnimplementedError();

  @override
  Future<AuthSession?> restoreSession() async => null;

  @override
  Future<void> signOut() async {}
}
