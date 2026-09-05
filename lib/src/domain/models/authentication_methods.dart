import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';

/// Interactive authentication methods advertised by a Mattermost server.
final class AuthenticationMethods {
  const AuthenticationMethods({
    required this.ssoOptions,
    required this.passwordLoginEnabled,
  });

  final List<SsoOption> ssoOptions;
  final bool passwordLoginEnabled;
}
