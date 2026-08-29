import 'package:mattermost_flutter/src/features/auth/domain/auth_failure.dart';
import 'package:mattermost_flutter/src/features/auth/domain/normalize_server_url.dart';
import 'package:mattermost_flutter/src/features/auth/domain/sso_provider.dart';

/// Validates and normalizes a user-supplied Mattermost server address.
///
/// Only HTTPS servers are accepted, apart from loopback servers used for local
/// development. Queries, fragments, and user-info are intentionally rejected:
/// this address identifies a server origin rather than a specific page.
Uri? tryNormalizeMattermostServerUrl(String value) {
  try {
    return const NormalizeServerUrl()(value);
  } on AuthFailure {
    return null;
  }
}

/// Builds the top-level Mattermost login URL without dropping a deployment's
/// path prefix (for example, `https://chat.example.com/mattermost`).
Uri buildSsoLoginUrl({required Uri serverUrl, required SsoProvider provider}) {
  final Uri? normalized = tryNormalizeMattermostServerUrl(serverUrl.toString());
  if (normalized == null) {
    throw ArgumentError.value(serverUrl, 'serverUrl', 'Invalid server URL');
  }

  final List<String> pathSegments = <String>[
    ...normalized.pathSegments.where((String segment) => segment.isNotEmpty),
    ...switch (provider) {
      SsoProvider.saml => const <String>['login', 'sso', 'saml'],
      SsoProvider.openId => const <String>['oauth', 'openid', 'mobile_login'],
    },
  ];
  return normalized.replace(
    pathSegments: pathSegments,
    queryParameters: provider == SsoProvider.saml
        ? const <String, String>{'action': 'mobile'}
        : null,
  );
}
