import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_failure.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_repository.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/auth/domain/authenticate_with_session_token.dart';

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

  test('rejects insecure non-local server URL without calling repository', () {
    final _FakeAuthRepository repository = _FakeAuthRepository();

    expect(
      () => AuthenticateWithSessionToken(repository)(
        serverUrl: 'http://chat.example.com',
        token: 'secret',
      ),
      throwsA(
        isA<AuthFailure>().having(
          (AuthFailure error) => error.kind,
          'kind',
          AuthFailureKind.invalidServer,
        ),
      ),
    );
    expect(repository.serverUrl, isNull);
  });
}

final class _FakeAuthRepository implements AuthRepository {
  Uri? serverUrl;
  String? token;

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
  Future<AuthSession?> restoreSession() async => null;

  @override
  Future<void> signOut() async {}
}
