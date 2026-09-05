import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_server_discovery.dart';
import 'package:mattermost_flutter/src/data/repositories/api_server_sso_discovery.dart';
import 'package:mattermost_flutter/src/domain/models/auth_failure.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';

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

    final methods = await ApiServerSsoDiscovery(
      clientFactory: factory,
    ).discover(Uri.parse('https://chat.example.com/mattermost'));

    expect(factory.serverUrl, Uri.parse('https://chat.example.com/mattermost'));
    expect(methods.ssoOptions, hasLength(1));
    expect(methods.ssoOptions.single.provider, SsoProvider.saml);
    expect(methods.ssoOptions.single.displayLabel, 'Company SAML');
    expect(methods.passwordLoginEnabled, isFalse);
    expect(client.closed, isTrue);
  });

  test('keeps both enabled methods in server order', () async {
    final methods = await ApiServerSsoDiscovery(
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

    expect(
      methods.ssoOptions.map((SsoOption option) => option.provider),
      <SsoProvider>[SsoProvider.saml, SsoProvider.openId],
    );
  });

  test('returns no SSO methods when all methods are disabled', () async {
    final _Client client = _Client.success(
      const MattermostClientConfigDto(
        enableSaml: false,
        samlLoginButtonText: '',
        enableSignUpWithOpenId: false,
        openIdButtonText: '',
      ),
    );

    final methods = await ApiServerSsoDiscovery(
      clientFactory: _Factory(client),
    ).discover(Uri.parse('https://chat.example.com'));

    expect(methods.ssoOptions, isEmpty);
    expect(client.closed, isTrue);
  });

  test(
    'enables password login for email or username server settings',
    () async {
      final methods = await ApiServerSsoDiscovery(
        clientFactory: _Factory(
          _Client.success(
            const MattermostClientConfigDto(
              enableSaml: false,
              samlLoginButtonText: '',
              enableSignUpWithOpenId: false,
              openIdButtonText: '',
              enableSignInWithUsername: true,
            ),
          ),
        ),
      ).discover(Uri.parse('https://chat.example.com'));

      expect(methods.passwordLoginEnabled, isTrue);
    },
  );

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
  Future<String> login({required String loginId, required String password}) =>
      throw UnimplementedError();

  @override
  void close() => closed = true;
}
