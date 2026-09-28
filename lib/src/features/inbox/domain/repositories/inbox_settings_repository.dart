import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_settings.dart';

/// Server-backed, client-owned settings for the Inbox projection.
///
/// Implementations scope every operation to [session]. They must not read or
/// write Mattermost desktop notification settings and must keep the separate
/// `postponed_messages` preference category untouched.
abstract class InboxSettingsRepository {
  const InboxSettingsRepository();

  Future<InboxSettingsSnapshot> load({required AuthSession session});

  Future<void> save({
    required AuthSession session,
    required InboxSettings settings,
  });
}
