import 'package:mattermost_flutter/src/features/auth/domain/sso_provider.dart';

/// Loads the SSO methods that an unauthenticated Mattermost server exposes.
///
/// [serverUrl] must have been normalized with
/// [tryNormalizeMattermostServerUrl] before this contract is called.
abstract interface class ServerSsoDiscovery {
  Future<List<SsoOption>> discover(Uri serverUrl);
}
