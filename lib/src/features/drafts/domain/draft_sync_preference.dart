abstract interface class DraftSyncPreference {
  Future<bool> isEnabled(String userId);
}
