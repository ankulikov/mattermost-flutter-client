abstract interface class CredentialStore {
  Future<void> save({required Uri serverUrl, required String token});

  Future<({Uri serverUrl, String token})?> read();

  Future<void> clear();
}
