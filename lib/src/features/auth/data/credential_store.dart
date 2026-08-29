abstract interface class CredentialStore {
  Future<void> save({required Uri serverUrl, required String token});

  Future<({Uri serverUrl, String token})?> read();

  Future<void> clear();
}

/// Thrown when secure storage contains only part of a credential pair or an
/// unusable server URL. It intentionally carries no credential values.
final class CredentialStoreCorruptionException implements Exception {
  const CredentialStoreCorruptionException();
}
