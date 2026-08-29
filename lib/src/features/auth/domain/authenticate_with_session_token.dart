import 'package:mattermost_flutter/src/features/auth/domain/auth_failure.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_repository.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/auth/domain/normalize_server_url.dart';

/// Validates and activates a session token received from a Mattermost login.
final class AuthenticateWithSessionToken {
  AuthenticateWithSessionToken(
    this._repository, {
    NormalizeServerUrl normalizeServerUrl = const NormalizeServerUrl(),
  }) : _normalizeServerUrl = normalizeServerUrl;

  final AuthRepository _repository;
  final NormalizeServerUrl _normalizeServerUrl;

  Future<AuthSession> call({required String serverUrl, required String token}) {
    final String normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      throw const AuthFailure(AuthFailureKind.tokenMissing);
    }
    return _repository.authenticateWithSessionToken(
      serverUrl: _normalizeServerUrl(serverUrl),
      token: normalizedToken,
    );
  }
}
