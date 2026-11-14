import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft_sync_preference.dart';

final class MattermostDraftSyncPreference implements DraftSyncPreference {
  const MattermostDraftSyncPreference(this._api);
  final MattermostApi _api;

  @override
  Future<bool> isEnabled(String userId) async {
    final preferences = await _api.getPreferencesByCategory(
      userId: userId,
      category: 'advanced_settings',
    );
    for (final preference in preferences) {
      if (preference.name == 'sync_drafts') return preference.value != 'false';
    }
    return true;
  }
}
