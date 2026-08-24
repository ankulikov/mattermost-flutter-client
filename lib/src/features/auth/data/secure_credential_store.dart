import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mattermost_flutter/src/features/auth/data/credential_store.dart';

final class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(
      mOptions: MacOsOptions(
        accessibility: KeychainAccessibility.first_unlock,
      ));

  static const String _serverKey = 'mattermost.active.server_url';
  static const String _tokenKey = 'mattermost.active.personal_access_token';

  final FlutterSecureStorage _storage;

  @override
  Future<void> save({required Uri serverUrl, required String token}) async {
    await _storage.write(key: _serverKey, value: serverUrl.toString());
    try {
      await _storage.write(key: _tokenKey, value: token);
    } on Object {
      await _storage.delete(key: _serverKey);
      rethrow;
    }
  }

  @override
  Future<({Uri serverUrl, String token})?> read() async {
    final List<String?> values = await Future.wait(<Future<String?>>[
      _storage.read(key: _serverKey),
      _storage.read(key: _tokenKey),
    ]);
    final Uri? serverUrl = Uri.tryParse(values[0] ?? '');
    final String? token = values[1];
    if (serverUrl == null ||
        serverUrl.host.isEmpty ||
        token == null ||
        token.isEmpty) {
      return null;
    }
    return (serverUrl: serverUrl, token: token);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _serverKey);
  }
}
