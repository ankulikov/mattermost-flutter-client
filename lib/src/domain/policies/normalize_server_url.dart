import 'package:mattermost_flutter/src/domain/models/auth_failure.dart';

/// Parses and canonicalizes a Mattermost server URL used by authentication.
///
/// A deployment path is preserved and trailing slashes are removed. For a
/// schemeless address, [candidates] supplies the protocol probe order.
final class NormalizeServerUrl {
  const NormalizeServerUrl();

  /// Returns server origins in the order they should be tried.
  ///
  /// Explicit `http` and `https` schemes are authoritative. Schemeless
  /// addresses normally try HTTPS before HTTP, while local development hosts
  /// try HTTP first.
  List<Uri> candidates(String value) {
    final String trimmed = value.trim();
    final bool hasExplicitScheme = RegExp(
      r'^[a-zA-Z][a-zA-Z0-9+.-]*://',
    ).hasMatch(trimmed);
    final Uri? parsed = Uri.tryParse(
      hasExplicitScheme ? trimmed : 'https://$trimmed',
    );
    if (parsed == null || !_isAllowed(parsed)) {
      throw const AuthFailure(AuthFailureKind.invalidServer);
    }

    final Uri normalized = _normalize(parsed);
    if (hasExplicitScheme) return <Uri>[normalized];

    final Uri http = normalized.replace(scheme: 'http');
    return _isLocalHost(normalized.host)
        ? <Uri>[http, normalized]
        : <Uri>[normalized, http];
  }

  /// Returns the preferred origin for a server address.
  Uri call(String value) => candidates(value).first;

  Uri _normalize(Uri parsed) {
    final String path = parsed.path.replaceFirst(RegExp(r'/+$'), '');
    return parsed.replace(
      scheme: parsed.scheme.toLowerCase(),
      host: parsed.host.toLowerCase(),
      path: path,
    );
  }

  bool _isAllowed(Uri uri) {
    return uri.hasScheme &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        (uri.scheme.toLowerCase() == 'https' ||
            uri.scheme.toLowerCase() == 'http');
  }

  bool _isLocalHost(String host) {
    final String normalizedHost = host.toLowerCase();
    return normalizedHost == 'localhost' ||
        normalizedHost == '127.0.0.1' ||
        normalizedHost == '::1' ||
        normalizedHost.startsWith('192.168') ||
        normalizedHost.endsWith('.lan') ||
        normalizedHost.endsWith('.local') ||
        normalizedHost.startsWith('100.64'); // tailscale
  }
}
