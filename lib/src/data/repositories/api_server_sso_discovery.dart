import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_server_discovery.dart';
import 'package:mattermost_flutter/src/domain/models/auth_failure.dart';
import 'package:mattermost_flutter/src/domain/models/authentication_methods.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';
import 'package:mattermost_flutter/src/domain/services/server_sso_discovery.dart';

/// Maps an unauthenticated Mattermost client config to interactive SSO options.
final class ApiServerSsoDiscovery implements ServerSsoDiscovery {
  ApiServerSsoDiscovery({
    MattermostServerDiscoveryClientFactory clientFactory =
        const DioMattermostServerDiscoveryClientFactory(),
  }) : _clientFactory = clientFactory;

  final MattermostServerDiscoveryClientFactory _clientFactory;

  @override
  Future<AuthenticationMethods> discover(Uri serverUrl) async {
    final MattermostServerDiscoveryClient client = _clientFactory.create(
      serverUrl: serverUrl,
    );
    try {
      final MattermostClientConfigDto config = await client.getClientConfig();
      final List<SsoOption> options = <SsoOption>[
        if (config.enableSaml)
          SsoOption(
            provider: SsoProvider.saml,
            displayLabel: config.samlLoginButtonText,
          ),
        if (config.enableSignUpWithOpenId)
          SsoOption(
            provider: SsoProvider.openId,
            displayLabel: config.openIdButtonText,
          ),
      ];
      return AuthenticationMethods(
        ssoOptions: List<SsoOption>.unmodifiable(options),
        passwordLoginEnabled:
            config.enableSignInWithEmail || config.enableSignInWithUsername,
      );
    } on AuthFailure {
      rethrow;
    } on MattermostServerDiscoveryNetworkException {
      throw const AuthFailure(AuthFailureKind.network);
    } on FormatException {
      throw const AuthFailure(AuthFailureKind.invalidResponse);
    } finally {
      client.close();
    }
  }
}
