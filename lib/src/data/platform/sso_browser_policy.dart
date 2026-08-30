import 'package:mattermost_flutter/src/features/auth/domain/sso_provider.dart';
import 'package:mattermost_flutter/src/features/auth/domain/sso_url.dart';

/// Pure validation and URL rules for the SSO browser boundary.
///
/// This deliberately contains no WebView API calls so its security-critical
/// behavior can be tested without a platform browser.
final class SsoBrowserPolicy {
  const SsoBrowserPolicy._();

  static const int maxSessionTokenLength = 4096;
  static const String sessionCookieName = 'MMAUTHTOKEN';

  static const Set<String> cookiesToClear = <String>{
    sessionCookieName,
    'MMUSERID',
    'MMCSRF',
  };

  static Uri startUrl({
    required Uri serverUrl,
    required SsoProvider provider,
  }) => buildSsoLoginUrl(serverUrl: serverUrl, provider: provider);

  static bool isValidServerUrl(Uri uri) =>
      tryNormalizeMattermostServerUrl(uri.toString()) != null;

  /// Only web navigations are permitted. Dangerous URL schemes are never
  /// handed to the platform or an external application from this boundary.
  /// Plain HTTP is limited to loopback development servers.
  static bool isAllowedNavigation(Uri uri) {
    if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return false;
    if (uri.scheme.toLowerCase() == 'https') return true;
    if (uri.scheme.toLowerCase() != 'http') return false;
    final String host = uri.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  static bool isExpectedReturn({
    required Uri serverUrl,
    required Uri navigationUrl,
  }) {
    if (!sameOrigin(serverUrl, navigationUrl)) {
      return false;
    }

    final String serverPath = _normalizedPath(serverUrl.path);
    final String navigationPath = _normalizedPath(navigationUrl.path);
    return serverPath == '/' ||
        navigationPath == serverPath ||
        navigationPath.startsWith('$serverPath/');
  }

  static bool sameOrigin(Uri first, Uri second) {
    return first.scheme.toLowerCase() == second.scheme.toLowerCase() &&
        first.host.toLowerCase() == second.host.toLowerCase() &&
        _effectivePort(first) == _effectivePort(second);
  }

  static String? sessionTokenFromCookies({
    required Uri serverUrl,
    required Iterable<SsoBrowserCookie> cookies,
  }) {
    for (final SsoBrowserCookie cookie in cookies) {
      if (cookie.name != sessionCookieName ||
          !_matchesExpectedServer(cookie, serverUrl)) {
        continue;
      }

      final String value = cookie.value;
      if (value.trim().isEmpty || value.length > maxSessionTokenLength) {
        return null;
      }
      return value;
    }
    return null;
  }

  static bool _matchesExpectedServer(SsoBrowserCookie cookie, Uri serverUrl) {
    final String? domain = cookie.domain;
    if (domain != null &&
        domain.isNotEmpty &&
        domain.replaceFirst(RegExp(r'^\.'), '').toLowerCase() !=
            serverUrl.host.toLowerCase()) {
      return false;
    }

    final String? cookiePath = cookie.path;
    if (cookiePath == null || cookiePath.isEmpty || cookiePath == '/') {
      return true;
    }
    final String serverPath = _normalizedPath(serverUrl.path);
    final String normalizedCookiePath = _normalizedPath(cookiePath);
    return serverPath == normalizedCookiePath ||
        serverPath.startsWith('$normalizedCookiePath/');
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) {
      return uri.port;
    }
    return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
  }

  static String _normalizedPath(String path) {
    if (path.isEmpty || path == '/') {
      return '/';
    }
    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }
}

/// Cookie data exposed to the policy. The adapter maps the native cookie type
/// into this value instead of letting plugin types cross the boundary.
final class SsoBrowserCookie {
  const SsoBrowserCookie({
    required this.name,
    required this.value,
    this.domain,
    this.path,
  });

  final String name;
  final String value;
  final String? domain;
  final String? path;
}
