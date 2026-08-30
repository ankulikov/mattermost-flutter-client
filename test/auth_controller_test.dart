import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/app/di/app_providers.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_failure.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_repository.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/auth/domain/server_sso_discovery.dart';
import 'package:mattermost_flutter/src/features/auth/domain/sso_browser_gateway.dart';
import 'package:mattermost_flutter/src/features/auth/domain/sso_provider.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/auth_controller.dart';

void main() {
  test(
    'discovers SSO then validates its transient browser session token',
    () async {
      final _RecordingAuthRepository repository = _RecordingAuthRepository();
      final _BrowserGateway browser = _BrowserGateway(
        const SsoBrowserSuccess('session-token'),
      );
      final ProviderContainer container = _container(
        repository: repository,
        discovery: const _Discovery(),
        browser: browser,
      );
      addTearDown(container.dispose);

      final AuthController controller = container.read(
        authControllerProvider.notifier,
      );
      await controller.discoverServer('https://chat.example.com/mattermost/');

      final AuthState choosing = container.read(authControllerProvider);
      expect(choosing.phase, AuthPhase.choosingSso);
      expect(
        choosing.serverUrl,
        Uri.parse('https://chat.example.com/mattermost'),
      );
      expect(choosing.ssoOptions.single.provider, SsoProvider.saml);

      await controller.authenticate(SsoProvider.saml);

      final AuthState signedIn = container.read(authControllerProvider);
      expect(signedIn.phase, AuthPhase.signedIn);
      expect(
        repository.serverUrl,
        Uri.parse('https://chat.example.com/mattermost'),
      );
      expect(repository.token, 'session-token');
      expect(signedIn.session?.username, 'ada');
    },
  );

  test(
    'returns to method chooser without an error when browser is cancelled',
    () async {
      final ProviderContainer container = _container(
        repository: _RecordingAuthRepository(),
        discovery: const _Discovery(),
        browser: _BrowserGateway(
          const SsoBrowserFailure(SsoBrowserFailureKind.cancelled),
        ),
      );
      addTearDown(container.dispose);

      final AuthController controller = container.read(
        authControllerProvider.notifier,
      );
      await controller.discoverServer('https://chat.example.com');
      await controller.authenticate(SsoProvider.saml);

      final AuthState state = container.read(authControllerProvider);
      expect(state.phase, AuthPhase.choosingSso);
      expect(state.failure, isNull);
    },
  );

  test(
    'validates a user-entered token without retaining it in state',
    () async {
      final _RecordingAuthRepository repository = _RecordingAuthRepository();
      final ProviderContainer container = _container(
        repository: repository,
        discovery: const _Discovery(),
        browser: _BrowserGateway(
          const SsoBrowserFailure(SsoBrowserFailureKind.cancelled),
        ),
      );
      addTearDown(container.dispose);

      final AuthController controller = container.read(
        authControllerProvider.notifier,
      );
      await controller.discoverServer('https://chat.example.com');
      controller.chooseTokenLogin();

      expect(
        container.read(authControllerProvider).phase,
        AuthPhase.enteringToken,
      );

      await controller.authenticateWithToken('  personal-access-token  ');

      final AuthState state = container.read(authControllerProvider);
      expect(state.phase, AuthPhase.signedIn);
      expect(repository.token, 'personal-access-token');
      expect(state.toString(), isNot(contains('personal-access-token')));
    },
  );

  test('offers token login when the server exposes no SSO methods', () async {
    final _RecordingAuthRepository repository = _RecordingAuthRepository();
    final ProviderContainer container = _container(
      repository: repository,
      discovery: const _EmptyDiscovery(),
      browser: _BrowserGateway(
        const SsoBrowserFailure(SsoBrowserFailureKind.cancelled),
      ),
    );
    addTearDown(container.dispose);

    final AuthController controller = container.read(
      authControllerProvider.notifier,
    );
    await controller.discoverServer('https://chat.example.com');
    controller.chooseTokenLogin();
    await controller.authenticateWithToken('personal-access-token');

    expect(container.read(authControllerProvider).phase, AuthPhase.signedIn);
    expect(repository.token, 'personal-access-token');
  });

  test('keeps an expired saved-session reason for the signed-out UI', () async {
    final ProviderContainer container = _container(
      repository: _RecordingAuthRepository(
        restoreFailure: const AuthFailure(AuthFailureKind.sessionExpired),
      ),
      discovery: const _Discovery(),
      browser: _BrowserGateway(
        const SsoBrowserFailure(SsoBrowserFailureKind.cancelled),
      ),
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).restore();

    final AuthState state = container.read(authControllerProvider);
    expect(state.phase, AuthPhase.signedOut);
    expect(state.failure, AuthFailureKind.sessionExpired);
  });
}

ProviderContainer _container({
  required AuthRepository repository,
  required ServerSsoDiscovery discovery,
  required SsoBrowserGateway browser,
}) => ProviderContainer(
  overrides: [
    authRepositoryProvider.overrideWithValue(repository),
    serverSsoDiscoveryProvider.overrideWithValue(discovery),
    ssoBrowserGatewayProvider.overrideWithValue(browser),
  ],
);

final class _Discovery implements ServerSsoDiscovery {
  const _Discovery();

  @override
  Future<List<SsoOption>> discover(Uri serverUrl) async => const <SsoOption>[
    SsoOption(provider: SsoProvider.saml, displayLabel: 'Company SSO'),
  ];
}

final class _BrowserGateway implements SsoBrowserGateway {
  const _BrowserGateway(this.result);

  final SsoBrowserResult result;

  @override
  Future<SsoBrowserResult> authenticate({
    required Uri serverUrl,
    required SsoProvider provider,
  }) async => result;

  @override
  Future<void> cancel() async {}
}

final class _EmptyDiscovery implements ServerSsoDiscovery {
  const _EmptyDiscovery();

  @override
  Future<List<SsoOption>> discover(Uri serverUrl) async => const <SsoOption>[];
}

final class _RecordingAuthRepository implements AuthRepository {
  _RecordingAuthRepository({this.restoreFailure});

  final AuthFailure? restoreFailure;
  Uri? serverUrl;
  String? token;

  @override
  Future<AuthSession> authenticateWithSessionToken({
    required Uri serverUrl,
    required String token,
  }) async {
    this.serverUrl = serverUrl;
    this.token = token;
    return AuthSession(serverUrl: serverUrl, userId: 'user-1', username: 'ada');
  }

  @override
  Future<AuthSession?> restoreSession() async {
    if (restoreFailure case final AuthFailure failure) throw failure;
    return null;
  }

  @override
  Future<void> signOut() async {}
}
