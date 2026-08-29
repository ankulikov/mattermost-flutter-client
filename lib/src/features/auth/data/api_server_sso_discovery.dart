import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_server_discovery.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_failure.dart';
import 'package:mattermost_flutter/src/features/auth/domain/server_sso_discovery.dart';
import 'package:mattermost_flutter/src/features/auth/domain/sso_provider.dart';

/// Maps Mattermost's unauthenticated client config to SSO domain options.
final class ApiServerSsoDiscovery implements ServerSsoDiscovery {
  ApiServerSsoDiscovery({
    MattermostServerDiscoveryClientFactory clientFactory =
        const DioMattermostServerDiscoveryClientFactory(),
  }) : _clientFactory = clientFactory;

  final MattermostServerDiscoveryClientFactory _clientFactory;

  @override
  Future<List<SsoOption>> discover(Uri serverUrl) async {
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
      if (options.isEmpty) {
        throw const AuthFailure(AuthFailureKind.ssoUnavailable);
      }
      return List<SsoOption>.unmodifiable(options);
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
