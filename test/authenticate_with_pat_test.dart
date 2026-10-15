import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_failure.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/authentication_methods.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';
import 'package:mattermost_flutter/src/domain/repositories/auth_repository.dart';
import 'package:mattermost_flutter/src/domain/use_cases/authenticate_with_session_token.dart';

void main() {
  test('normalizes input and delegates valid credentials', () async {
    final _FakeAuthRepository repository = _FakeAuthRepository();

    await AuthenticateWithSessionToken(repository)(
      serverUrl: '  HTTPS://chat.example.com/mattermost/  ',
      token: '  secret  ',
    );

    expect(
      repository.serverUrl,
      Uri.parse('https://chat.example.com/mattermost'),
    );
    expect(repository.token, 'secret');
  });

  test('rejects an explicit HTTP remote server URL', () async {
    final _FakeAuthRepository repository = _FakeAuthRepository();

    await expectLater(
      () => AuthenticateWithSessionToken(repository)(
        serverUrl: 'http://chat.example.com',
        token: 'secret',
      ),
      throwsA(isA<AuthFailure>()),
    );
  });
}

final class _FakeAuthRepository implements AuthRepository {
  Uri? serverUrl;
  String? token;

  @override
  Future<AuthSession> authenticateWithPassword({
    required Uri serverUrl,
    required String loginId,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<AuthenticationMethods> discoverAuthenticationMethods({
    required Uri serverUrl,
  }) => throw UnimplementedError();

  @override
  Future<AuthSession> authenticateWithSessionToken({
    required Uri serverUrl,
    required String token,
  }) async {
    this.serverUrl = serverUrl;
    this.token = token;
    return AuthSession(
      serverUrl: serverUrl,
      userId: 'user-id',
      username: 'user',
    );
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
      const <SsoOption>[];

  @override
  Future<AuthSession?> restoreSession() async => null;

  @override
  Future<void> signOut() async {}
}
