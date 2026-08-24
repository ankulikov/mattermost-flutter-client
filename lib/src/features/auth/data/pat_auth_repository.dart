import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/features/auth/data/credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_failure.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_repository.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';

final class PatAuthRepository implements AuthRepository {
  const PatAuthRepository({
    required CredentialStore credentialStore,
    MattermostClientFactory clientFactory = const MattermostClientFactory(),
  }) : _credentialStore = credentialStore,
       _clientFactory = clientFactory;

  final CredentialStore _credentialStore;
  final MattermostClientFactory _clientFactory;

  @override
  Future<AuthSession> authenticateWithPersonalAccessToken({
    required Uri serverUrl,
    required String token,
  }) async {
    final AuthSession session = await _validate(serverUrl, token);
    try {
      await _credentialStore.save(serverUrl: serverUrl, token: token);
    } on Object {
      throw const AuthFailure(AuthFailureKind.storage);
    }
    return session;
  }

  @override
  Future<AuthSession?> restoreSession() async {
    final ({Uri serverUrl, String token})? credentials;
    try {
      credentials = await _credentialStore.read();
    } on Object {
      throw const AuthFailure(AuthFailureKind.storage);
    }
    if (credentials == null) return null;
    return _validate(credentials.serverUrl, credentials.token);
  }

  @override
  Future<void> signOut() => _credentialStore.clear();

  Future<AuthSession> _validate(Uri serverUrl, String token) async {
    final MattermostApi api = _clientFactory.create(
      serverUrl: serverUrl,
      token: token,
    );
    try {
      final MattermostUserDto user = await api.getCurrentUser();
      if (user.id.isEmpty || user.username.isEmpty) {
        throw const AuthFailure(AuthFailureKind.invalidResponse);
      }
      return AuthSession(
        serverUrl: serverUrl,
        userId: user.id,
        username: user.username,
      );
    } on DioException catch (error) {
      final int? status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        throw const AuthFailure(AuthFailureKind.invalidCredentials);
      }
      throw const AuthFailure(AuthFailureKind.network);
    } on FormatException {
      throw const AuthFailure(AuthFailureKind.invalidResponse);
    }
  }
}
