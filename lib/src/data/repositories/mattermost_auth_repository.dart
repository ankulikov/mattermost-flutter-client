import 'package:dio/dio.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/data/platform/in_app_webview_sso_browser_gateway.dart';
import 'package:mattermost_flutter/src/data/repositories/api_server_sso_discovery.dart';
import 'package:mattermost_flutter/src/data/session/active_account_context.dart';
import 'package:mattermost_flutter/src/data/storage/credential_store.dart';
import 'package:mattermost_flutter/src/domain/models/auth_failure.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/sso_browser_result.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';
import 'package:mattermost_flutter/src/domain/policies/normalize_server_url.dart';
import 'package:mattermost_flutter/src/domain/repositories/auth_repository.dart';
import 'package:mattermost_flutter/src/domain/services/server_sso_discovery.dart';
import 'package:mattermost_flutter/src/domain/services/sso_browser_gateway.dart';

/// Owns the complete authentication workflow for the active Mattermost
/// account: public discovery, browser SSO hand-off, token validation, secure
/// persistence and the closeable authenticated transport.
class MattermostAuthRepository implements AuthRepository {
  MattermostAuthRepository({
    required CredentialStore credentialStore,
    ActiveAccountContext? activeAccount,
    MattermostApiClientFactory clientFactory = const MattermostClientFactory(),
    ServerSsoDiscovery? serverSsoDiscovery,
    SsoBrowserGateway? ssoBrowserGateway,
  }) : _credentialStore = credentialStore,
       _activeAccount = activeAccount ?? ActiveAccountContext(),
       _clientFactory = clientFactory,
       _serverSsoDiscovery = serverSsoDiscovery ?? ApiServerSsoDiscovery(),
       _ssoBrowserGateway =
           ssoBrowserGateway ?? InAppWebViewSsoBrowserGateway();

  final CredentialStore _credentialStore;
  final ActiveAccountContext _activeAccount;
  final MattermostApiClientFactory _clientFactory;
  final ServerSsoDiscovery _serverSsoDiscovery;
  final SsoBrowserGateway _ssoBrowserGateway;

  /// Compatibility projection; authenticated feature repositories receive the
  /// API through [ActiveAccountContext] instead.
  MattermostApi? get api => _activeAccount.api;

  @override
  Future<List<SsoOption>> discoverSsoOptions({required Uri serverUrl}) =>
      _serverSsoDiscovery.discover(serverUrl);

  @override
  Future<AuthSession> authenticateWithSso({
    required Uri serverUrl,
    required SsoProvider provider,
  }) async {
    final SsoBrowserResult browserResult;
    try {
      browserResult = await _ssoBrowserGateway.authenticate(
        serverUrl: serverUrl,
        provider: provider,
      );
    } on Object {
      throw const AuthFailure(AuthFailureKind.ssoFailed);
    }

    return switch (browserResult) {
      SsoBrowserSuccess(:final String sessionToken) =>
        authenticateWithSessionToken(serverUrl: serverUrl, token: sessionToken),
      SsoBrowserFailure(:final SsoBrowserFailureKind kind) => throw AuthFailure(
        _browserFailure(kind),
      ),
    };
  }

  @override
  Future<void> cancelSsoAuthentication() => _ssoBrowserGateway.cancel();

  @override
  Future<AuthSession> authenticateWithSessionToken({
    required Uri serverUrl,
    required String token,
  }) async {
    final ({MattermostApiClient client, AuthSession session}) validated =
        await _validate(serverUrl, token);
    try {
      await _credentialStore.save(serverUrl: serverUrl, token: token);
    } on Object {
      validated.client.close();
      throw const AuthFailure(AuthFailureKind.storage);
    }
    _activate(validated);
    return validated.session;
  }

  @override
  Future<AuthSession?> restoreSession() async {
    final ({Uri serverUrl, String token})? credentials;
    try {
      credentials = await _credentialStore.read();
    } on CredentialStoreCorruptionException {
      await _clearInvalidCredentials();
      throw const AuthFailure(AuthFailureKind.sessionExpired);
    } on Object {
      throw const AuthFailure(AuthFailureKind.storage);
    }
    if (credentials == null) return null;

    final Uri serverUrl;
    try {
      serverUrl = const NormalizeServerUrl()(credentials.serverUrl.toString());
    } on AuthFailure {
      await _clearInvalidCredentials();
      throw const AuthFailure(AuthFailureKind.sessionExpired);
    }

    try {
      final ({MattermostApiClient client, AuthSession session}) validated =
          await _validate(serverUrl, credentials.token);
      _activate(validated);
      return validated.session;
    } on AuthFailure catch (error) {
      if (error.kind != AuthFailureKind.invalidCredentials) rethrow;
      await _clearInvalidCredentials();
      throw const AuthFailure(AuthFailureKind.sessionExpired);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await cancelSsoAuthentication();
      await _credentialStore.clear();
    } finally {
      _deactivate();
    }
  }

  Future<({MattermostApiClient client, AuthSession session})> _validate(
    Uri serverUrl,
    String token,
  ) async {
    final MattermostApiClient client = _clientFactory.create(
      serverUrl: serverUrl,
      token: token,
    );
    try {
      final MattermostUserDto user = await client.api.getCurrentUser();
      if (user.id.isEmpty || user.username.isEmpty) {
        throw const AuthFailure(AuthFailureKind.invalidResponse);
      }
      return (
        client: client,
        session: AuthSession(
          serverUrl: serverUrl,
          userId: user.id,
          username: user.username,
        ),
      );
    } on AuthFailure {
      client.close();
      rethrow;
    } on DioException catch (error) {
      client.close();
      final int? status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        throw const AuthFailure(AuthFailureKind.invalidCredentials);
      }
      throw const AuthFailure(AuthFailureKind.network);
    } on FormatException {
      client.close();
      throw const AuthFailure(AuthFailureKind.invalidResponse);
    } on Object {
      client.close();
      rethrow;
    }
  }

  Future<void> _clearInvalidCredentials() async {
    _deactivate();
    try {
      await _credentialStore.clear();
    } on Object {
      throw const AuthFailure(AuthFailureKind.storage);
    }
  }

  void _activate(
    ({MattermostApiClient client, AuthSession session}) validated,
  ) => _activeAccount.activate(
    client: validated.client,
    session: validated.session,
  );

  void _deactivate() => _activeAccount.deactivate();

  void dispose() => _deactivate();

  AuthFailureKind _browserFailure(SsoBrowserFailureKind kind) => switch (kind) {
    SsoBrowserFailureKind.browserUnavailable =>
      AuthFailureKind.browserUnavailable,
    SsoBrowserFailureKind.invalidServer => AuthFailureKind.invalidServer,
    SsoBrowserFailureKind.tokenMissing => AuthFailureKind.tokenMissing,
    SsoBrowserFailureKind.cancelled => AuthFailureKind.cancelled,
    SsoBrowserFailureKind.unsafeNavigation ||
    SsoBrowserFailureKind.popupBlocked ||
    SsoBrowserFailureKind.loadingFailed ||
    SsoBrowserFailureKind.cookieStore => AuthFailureKind.ssoFailed,
  };
}

/// Compatibility name for code that still imports the previous PAT-specific
/// repository. New code should use [MattermostAuthRepository].
@Deprecated('Use MattermostAuthRepository.')
final class PatAuthRepository extends MattermostAuthRepository {
  PatAuthRepository({
    required super.credentialStore,
    super.clientFactory = const MattermostClientFactory(),
  });
}
