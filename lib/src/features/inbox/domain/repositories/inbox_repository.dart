import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';

abstract class InboxRepository {
  const InboxRepository();

  /// Loads an atomically reconciled, network-first Inbox projection.
  Future<InboxSnapshot> load({required AuthSession session});

  /// Emits connection state and realtime Inbox deltas. The default keeps
  /// simple/offline repository implementations source-compatible.
  Stream<InboxRealtimeEvent> watch({required AuthSession session}) =>
      const Stream<InboxRealtimeEvent>.empty();

  /// Advances the server read boundary represented by [item].
  Future<void> markRead({
    required AuthSession session,
    required InboxItem item,
  });
}
