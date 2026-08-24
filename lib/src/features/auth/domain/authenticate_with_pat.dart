import 'package:mattermost_flutter/src/features/auth/domain/auth_failure.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_repository.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';

final class AuthenticateWithPat {
  const AuthenticateWithPat(this._repository);

  final AuthRepository _repository;

  Future<AuthSession> call({required String serverUrl, required String token}) {
    final Uri? uri = Uri.tryParse(serverUrl.trim());
    final bool isLocalHost =
        uri?.host == 'localhost' || uri?.host == '127.0.0.1';
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' && !(isLocalHost && uri.scheme == 'http'))) {
      throw const AuthFailure(AuthFailureKind.invalidResponse);
    }
    if (token.trim().isEmpty) {
      throw const AuthFailure(AuthFailureKind.invalidCredentials);
    }

    return _repository.authenticateWithPersonalAccessToken(
      serverUrl: uri.replace(path: uri.path.replaceFirst(RegExp(r'/$'), '')),
      token: token.trim(),
    );
  }
}
