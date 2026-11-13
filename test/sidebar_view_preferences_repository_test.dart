import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/repositories/shared_preferences_sidebar_view_preferences_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/sidebar_view_preferences_repository.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('restores sidebar choices and isolates accounts', () async {
    final SidebarViewPreferencesRepository repository =
        SharedPreferencesSidebarViewPreferencesRepository();
    const String firstAccount = 'https://chat.example.com|user:first';
    const String secondAccount = 'https://chat.example.com|user:second';

    final SidebarViewPreferences initial = await repository.read(firstAccount);
    expect(initial.hideReadChannels, isFalse);
    expect(initial.hideFolderHeadings, isFalse);
    expect(initial.showUnreadInCollapsedFolders, isTrue);

    await repository.write(
      firstAccount,
      const SidebarViewPreferences(
        hideReadChannels: true,
        hideFolderHeadings: true,
        showUnreadInCollapsedFolders: false,
      ),
    );

    final SidebarViewPreferences restored =
        await SharedPreferencesSidebarViewPreferencesRepository().read(
          firstAccount,
        );
    expect(restored.hideReadChannels, isTrue);
    expect(restored.hideFolderHeadings, isTrue);
    expect(restored.showUnreadInCollapsedFolders, isFalse);

    final SidebarViewPreferences other = await repository.read(secondAccount);
    expect(other.hideReadChannels, isFalse);
    expect(other.hideFolderHeadings, isFalse);
    expect(other.showUnreadInCollapsedFolders, isTrue);
  });
}
