import 'package:mattermost_flutter/src/domain/repositories/sidebar_view_preferences_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesSidebarViewPreferencesRepository
    implements SidebarViewPreferencesRepository {
  SharedPreferencesSidebarViewPreferencesRepository()
    : _storage = SharedPreferencesAsync();

  final SharedPreferencesAsync _storage;

  String _key(String accountScopeId) =>
      'mattermost.sidebar.view.${Uri.encodeComponent(accountScopeId)}';

  @override
  Future<SidebarViewPreferences> read(String accountScopeId) async {
    final int flags = await _storage.getInt(_key(accountScopeId)) ?? 0;
    return SidebarViewPreferences(
      hideReadChannels: flags & 1 != 0,
      hideFolderHeadings: flags & 2 != 0,
    );
  }

  @override
  Future<void> write(
    String accountScopeId,
    SidebarViewPreferences preferences,
  ) => _storage.setInt(
    _key(accountScopeId),
    (preferences.hideReadChannels ? 1 : 0) |
        (preferences.hideFolderHeadings ? 2 : 0),
  );
}
