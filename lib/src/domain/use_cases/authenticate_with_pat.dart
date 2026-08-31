import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/repositories/auth_repository.dart';
import 'package:mattermost_flutter/src/domain/use_cases/authenticate_with_session_token.dart';

/// Legacy compatibility wrapper for the former PAT-only login flow.
@Deprecated('Use AuthenticateWithSessionToken.')
final class AuthenticateWithPat {
  AuthenticateWithPat(AuthRepository repository)
    : _delegate = AuthenticateWithSessionToken(repository);

  final AuthenticateWithSessionToken _delegate;

  Future<AuthSession> call({required String serverUrl, required String token}) {
    return _delegate(serverUrl: serverUrl, token: token);
  }
}
