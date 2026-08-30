import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';

abstract interface class AuthRepository {
  /// Discovers the interactive sign-on methods available for [serverUrl].
  ///
  /// This keeps public-server discovery inside the auth workflow rather than
  /// exposing a second auth dependency to presentation code.
  Future<List<SsoOption>> discoverSsoOptions({required Uri serverUrl});

  /// Validates a transient Mattermost session token and persists it only after
  /// the server has accepted it.
  ///
  /// The token must not be retained in presentation state or domain entities.
  Future<AuthSession> authenticateWithSessionToken({
    required Uri serverUrl,
    required String token,
  });

  /// Completes a browser SSO flow, validates its short-lived token and then
  /// persists and activates the authenticated account.
  Future<AuthSession> authenticateWithSso({
    required Uri serverUrl,
    required SsoProvider provider,
  });

  /// Cancels an in-progress browser SSO attempt.
  Future<void> cancelSsoAuthentication();

  Future<AuthSession?> restoreSession();

  Future<void> signOut();
}
