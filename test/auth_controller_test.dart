import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_failure.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';
import 'package:mattermost_flutter/src/domain/repositories/auth_repository.dart';
import 'package:mattermost_flutter/src/ui/auth/auth_controller.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  test(
    'discovers SSO then validates its transient browser session token',
    () async {
      final _RecordingAuthRepository repository = _RecordingAuthRepository();
      final ProviderContainer container = _container(repository: repository);
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
        repository: _RecordingAuthRepository(
          ssoFailure: const AuthFailure(AuthFailureKind.cancelled),
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
      final ProviderContainer container = _container(repository: repository);
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
    final _RecordingAuthRepository repository = _RecordingAuthRepository(
      options: const <SsoOption>[],
    );
    final ProviderContainer container = _container(repository: repository);
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
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).restore();

    final AuthState state = container.read(authControllerProvider);
    expect(state.phase, AuthPhase.signedOut);
    expect(state.failure, AuthFailureKind.sessionExpired);
  });
}

ProviderContainer _container({required AuthRepository repository}) =>
    ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );

final class _RecordingAuthRepository implements AuthRepository {
  _RecordingAuthRepository({
    this.restoreFailure,
    this.ssoFailure,
    this.options = const <SsoOption>[
      SsoOption(provider: SsoProvider.saml, displayLabel: 'Company SSO'),
    ],
  });

  final AuthFailure? restoreFailure;
  final AuthFailure? ssoFailure;
  final List<SsoOption> options;
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
  Future<AuthSession> authenticateWithSso({
    required Uri serverUrl,
    required SsoProvider provider,
  }) {
    if (ssoFailure case final AuthFailure failure) {
      return Future<AuthSession>.error(failure);
    }
    return authenticateWithSessionToken(
      serverUrl: serverUrl,
      token: 'session-token',
    );
  }

  @override
  Future<void> cancelSsoAuthentication() async {}

  @override
  Future<List<SsoOption>> discoverSsoOptions({required Uri serverUrl}) async =>
      options;

  @override
  Future<AuthSession?> restoreSession() async {
    if (restoreFailure case final AuthFailure failure) throw failure;
    return null;
  }

  @override
  Future<void> signOut() async {}
}
