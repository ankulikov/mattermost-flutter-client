import 'package:mattermost_flutter/src/domain/models/authentication_methods.dart';

/// Loads the interactive sign-on methods exposed by an unauthenticated server.
///
/// [serverUrl] must be normalized before this service is called. The auth data
/// implementation uses this only inside the [AuthRepository] workflow.
abstract interface class ServerSsoDiscovery {
  Future<AuthenticationMethods> discover(Uri serverUrl);
}
