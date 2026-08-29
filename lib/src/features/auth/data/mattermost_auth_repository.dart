import 'package:dio/dio.dart';
import 'package:mattermost_flutter/src/core/api/active_mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/features/auth/data/credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_failure.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_repository.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/auth/domain/normalize_server_url.dart';

/// Owns the authenticated API transport for the single active Mattermost
/// account. Both SSO and legacy PAT entry points use [authenticateWithSessionToken]
/// so validation, storage and activation cannot drift apart.
class MattermostAuthRepository implements AuthRepository, ActiveMattermostApi {
  MattermostAuthRepository({
    required CredentialStore credentialStore,
    MattermostApiClientFactory clientFactory = const MattermostClientFactory(),
  }) : _credentialStore = credentialStore,
       _clientFactory = clientFactory;

  final CredentialStore _credentialStore;
  final MattermostApiClientFactory _clientFactory;
  MattermostApiClient? _activeClient;

  @override
  MattermostApi? get api => _activeClient?.api;

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
    _activate(validated.client);
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
      _activate(validated.client);
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

  void _activate(MattermostApiClient client) {
    final MattermostApiClient? previous = _activeClient;
    _activeClient = client;
    previous?.close();
  }

  void _deactivate() {
    final MattermostApiClient? client = _activeClient;
    _activeClient = null;
    client?.close();
  }

  void dispose() => _deactivate();
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
