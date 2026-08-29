import 'package:mattermost_flutter/src/features/auth/domain/auth_failure.dart';

/// Parses and canonicalizes a Mattermost server URL used by authentication.
///
/// HTTPS is required except for local development servers.  A Mattermost
/// installation path is preserved, while trailing slashes are removed so API
/// and SSO endpoint builders have one stable base representation.
final class NormalizeServerUrl {
  const NormalizeServerUrl();

  Uri call(String value) {
    final Uri? parsed = Uri.tryParse(value.trim());
    if (parsed == null || !_isAllowed(parsed)) {
      throw const AuthFailure(AuthFailureKind.invalidServer);
    }

    final String path = parsed.path.replaceFirst(RegExp(r'/+$'), '');
    return parsed.replace(
      scheme: parsed.scheme.toLowerCase(),
      host: parsed.host.toLowerCase(),
      path: path,
    );
  }

  bool _isAllowed(Uri uri) {
    final String host = uri.host.toLowerCase();
    final bool isLocalHost =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    return uri.hasScheme &&
        host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        (uri.scheme.toLowerCase() == 'https' ||
            (isLocalHost && uri.scheme.toLowerCase() == 'http'));
  }
}
