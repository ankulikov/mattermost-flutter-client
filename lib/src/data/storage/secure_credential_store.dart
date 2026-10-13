import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mattermost_flutter/src/data/storage/credential_store.dart';
import 'package:mattermost_flutter/src/data/storage/keychain_owner_repair.dart';
import 'package:mattermost_flutter/src/data/storage/keychain_repair_result.dart';
import 'package:mattermost_flutter/src/domain/policies/normalize_server_url.dart';

typedef KeychainOwnerRepair =
    Future<KeychainRepairResult> Function({
      required String key,
      required String service,
    });

final class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore({
    FlutterSecureStorage? storage,
    KeychainOwnerRepair? keychainOwnerRepair,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             mOptions: MacOsOptions(
               accessibility: KeychainAccessibility.first_unlock,
               // Ad-hoc macOS release builds cannot authorize the entitlement
               // required by the Data Protection Keychain. Use the legacy
               // file-based Keychain until macOS distribution signing is set up.
               usesDataProtectionKeychain: false,
             ),
           ),
       _keychainOwnerRepair =
           keychainOwnerRepair ?? repairInaccessibleMacOsKeychainItem;

  static const String _serverKey = 'mattermost.active.server_url';
  static const String _sessionTokenKey = 'mattermost.active.session_token';
  static const String _legacyPatTokenKey =
      'mattermost.active.personal_access_token';

  final FlutterSecureStorage _storage;
  final KeychainOwnerRepair _keychainOwnerRepair;

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
    for (final String key in <String>[
      _sessionTokenKey,
      _legacyPatTokenKey,
      _serverKey,
    ]) {
      try {
        await _storage.delete(key: key);
      } on PlatformException catch (error) {
        // An item created under a different macOS Keychain ACL can be readable
        // but reject the plugin's SecItemDelete with errSecInvalidOwnerEdit.
        if (error.details != -25244) rethrow;
        final KeychainRepairResult result = await _keychainOwnerRepair(
          key: key,
          service: AppleOptions.defaultAccountName,
        );
        if (result == KeychainRepairResult.failed ||
            (result == KeychainRepairResult.absent &&
                await _storage.read(key: key) != null)) {
          rethrow;
        }
      }
      if (!await _ensureAbsent(key)) {
        throw const CredentialStoreCorruptionException();
      }
    }
  }

  Future<bool> _ensureAbsent(String key) async {
    for (int attempt = 0; attempt < 3; attempt += 1) {
      if (await _storage.read(key: key) == null) return true;
      if (await _keychainOwnerRepair(
            key: key,
            service: AppleOptions.defaultAccountName,
          ) !=
          KeychainRepairResult.removed) {
        return false;
      }
    }
    return await _storage.read(key: key) == null;
  }
}
