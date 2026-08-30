import 'package:mattermost_flutter/src/domain/models/auth_session.dart';

abstract interface class AuthRepository {
  /// Validates a transient Mattermost session token and persists it only after
  /// the server has accepted it.
  ///
  /// The token must not be retained in presentation state or domain entities.
  Future<AuthSession> authenticateWithSessionToken({
    required Uri serverUrl,
    required String token,
  });

  Future<AuthSession?> restoreSession();

  Future<void> signOut();
}
