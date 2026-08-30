import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mattermost_flutter/src/data/storage/credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/normalize_server_url.dart';

final class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  static const String _serverKey = 'mattermost.active.server_url';
  static const String _sessionTokenKey = 'mattermost.active.session_token';
  static const String _legacyPatTokenKey =
      'mattermost.active.personal_access_token';

  final FlutterSecureStorage _storage;

  @override
  Future<void> save({required Uri serverUrl, required String token}) async {
    try {
      await _storage.write(key: _serverKey, value: serverUrl.toString());
      await _storage.write(key: _sessionTokenKey, value: token);
    } on Object {
      try {
        await clear();
      } on Object {
        // Preserve the original write failure without exposing secure values.
      }
      rethrow;
    }
    try {
      await _storage.delete(key: _legacyPatTokenKey);
    } on Object {
      // The new token is authoritative; a failed best-effort legacy cleanup
      // must not discard a successfully saved session.
    }
  }

  @override
  Future<({Uri serverUrl, String token})?> read() async {
    final List<String?> values = await Future.wait(<Future<String?>>[
      _storage.read(key: _serverKey),
      _storage.read(key: _sessionTokenKey),
      _storage.read(key: _legacyPatTokenKey),
    ]);
    final String? serverUrlValue = values[0];
    final String? token = values[1] ?? values[2];
    if (serverUrlValue == null && token == null) {
      return null;
    }
    if (serverUrlValue == null || token == null || token.isEmpty) {
      throw const CredentialStoreCorruptionException();
    }

    final Uri serverUrl;
    try {
      serverUrl = const NormalizeServerUrl()(serverUrlValue);
    } on Object {
      throw const CredentialStoreCorruptionException();
    }

    if (values[1] == null) {
      try {
        await _storage.write(key: _sessionTokenKey, value: token);
        await _storage.delete(key: _legacyPatTokenKey);
      } on Object {
        // The legacy key remains a valid fallback on the next startup.
      }
    }
    return (serverUrl: serverUrl, token: token);
  }

  @override
  Future<void> clear() async {
    await Future.wait(<Future<void>>[
      _storage.delete(key: _sessionTokenKey),
      _storage.delete(key: _legacyPatTokenKey),
      _storage.delete(key: _serverKey),
    ]);
  }
}
