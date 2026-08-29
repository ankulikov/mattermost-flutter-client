import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_server_discovery.dart';
import 'package:mattermost_flutter/src/features/auth/data/api_server_sso_discovery.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_failure.dart';
import 'package:mattermost_flutter/src/features/auth/domain/sso_provider.dart';

void main() {
  test('maps only SSO methods enabled by the server', () async {
    final _Client client = _Client.success(
      const MattermostClientConfigDto(
        enableSaml: true,
        samlLoginButtonText: 'Company SAML',
        enableSignUpWithOpenId: false,
        openIdButtonText: 'OpenID Connect',
      ),
    );
    final _Factory factory = _Factory(client);

    final options = await ApiServerSsoDiscovery(
      clientFactory: factory,
    ).discover(Uri.parse('https://chat.example.com/mattermost'));

    expect(factory.serverUrl, Uri.parse('https://chat.example.com/mattermost'));
    expect(options, hasLength(1));
    expect(options.single.provider, SsoProvider.saml);
    expect(options.single.displayLabel, 'Company SAML');
    expect(client.closed, isTrue);
  });

  test('keeps both enabled methods in server order', () async {
    final options = await ApiServerSsoDiscovery(
      clientFactory: _Factory(
        _Client.success(
          const MattermostClientConfigDto(
            enableSaml: true,
            samlLoginButtonText: 'SAML',
            enableSignUpWithOpenId: true,
            openIdButtonText: 'OpenID',
          ),
        ),
      ),
    ).discover(Uri.parse('https://chat.example.com'));

    expect(options.map((SsoOption option) => option.provider), <SsoProvider>[
      SsoProvider.saml,
      SsoProvider.openId,
    ]);
  });

  test('reports unavailable SSO when all methods are disabled', () async {
    final _Client client = _Client.success(
      const MattermostClientConfigDto(
        enableSaml: false,
        samlLoginButtonText: '',
        enableSignUpWithOpenId: false,
        openIdButtonText: '',
      ),
    );

    await expectLater(
      ApiServerSsoDiscovery(
        clientFactory: _Factory(client),
      ).discover(Uri.parse('https://chat.example.com')),
      throwsA(
        isA<AuthFailure>().having(
          (AuthFailure failure) => failure.kind,
          'kind',
          AuthFailureKind.ssoUnavailable,
        ),
      ),
    );
    expect(client.closed, isTrue);
  });

  test('maps a discovery transport failure without exposing Dio', () async {
    final _Client client = _Client.failure(
      const MattermostServerDiscoveryNetworkException(),
    );

    await expectLater(
      ApiServerSsoDiscovery(
        clientFactory: _Factory(client),
      ).discover(Uri.parse('https://chat.example.com')),
      throwsA(
        isA<AuthFailure>().having(
          (AuthFailure failure) => failure.kind,
          'kind',
          AuthFailureKind.network,
        ),
      ),
    );
    expect(client.closed, isTrue);
  });
}

final class _Factory implements MattermostServerDiscoveryClientFactory {
  _Factory(this.client);

  final _Client client;
  Uri? serverUrl;

  @override
  MattermostServerDiscoveryClient create({required Uri serverUrl}) {
    this.serverUrl = serverUrl;
    return client;
  }
}

final class _Client implements MattermostServerDiscoveryClient {
  _Client.success(MattermostClientConfigDto this.config) : error = null;

  _Client.failure(Object this.error) : config = null;

  final MattermostClientConfigDto? config;
  final Object? error;
  bool closed = false;

  @override
  Future<MattermostClientConfigDto> getClientConfig() async {
    if (error != null) throw error!;
    return config!;
  }

  @override
  void close() => closed = true;
}
