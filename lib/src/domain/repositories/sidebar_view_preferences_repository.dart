final class SidebarViewPreferences {
  const SidebarViewPreferences({
    this.hideReadChannels = false,
    this.hideFolderHeadings = false,
  });

  final bool hideReadChannels;
  final bool hideFolderHeadings;
}

abstract interface class SidebarViewPreferencesRepository {
  Future<SidebarViewPreferences> read(String accountScopeId);

  Future<void> write(String accountScopeId, SidebarViewPreferences preferences);
}
