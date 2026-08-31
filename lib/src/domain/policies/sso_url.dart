import 'package:mattermost_flutter/src/domain/models/auth_failure.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';
import 'package:mattermost_flutter/src/domain/policies/normalize_server_url.dart';

/// Validates and normalizes a user-supplied Mattermost server address.
Uri? tryNormalizeMattermostServerUrl(String value) {
  try {
    return const NormalizeServerUrl()(value);
  } on AuthFailure {
    return null;
  }
}

/// Builds the top-level Mattermost login URL without dropping a deployment
/// path prefix.
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
