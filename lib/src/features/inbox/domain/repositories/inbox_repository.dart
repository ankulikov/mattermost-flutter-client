import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';

abstract class InboxRepository {
  const InboxRepository();

  /// Loads an atomically reconciled, network-first Inbox projection.
  Future<InboxSnapshot> load({required AuthSession session});

  /// Advances the server read boundary represented by [item].
  Future<void> markRead({
    required AuthSession session,
    required InboxItem item,
  });
}
