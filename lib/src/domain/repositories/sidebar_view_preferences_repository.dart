final class SidebarViewPreferences {
  const SidebarViewPreferences({
    this.hideReadChannels = false,
    this.hideFolderHeadings = false,
    this.showUnreadInCollapsedFolders = true,
  });

  final bool hideReadChannels;
  final bool hideFolderHeadings;
  final bool showUnreadInCollapsedFolders;
}

abstract interface class SidebarViewPreferencesRepository {
  Future<SidebarViewPreferences> read(String accountScopeId);

  Future<void> write(String accountScopeId, SidebarViewPreferences preferences);
}
