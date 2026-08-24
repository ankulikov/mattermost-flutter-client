import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';

abstract interface class AuthRepository {
  Future<AuthSession> authenticateWithPersonalAccessToken({
    required Uri serverUrl,
    required String token,
  });

  Future<AuthSession?> restoreSession();

  Future<void> signOut();
}
