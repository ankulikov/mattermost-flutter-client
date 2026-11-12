import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_counters.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';

abstract class InboxRepository {
  const InboxRepository();

  /// Loads the last content-free counts stored for this account.
  ///
  /// Implementations without durable storage keep the zero-count default.
  Future<InboxCounters> loadCounters({required AuthSession session}) async =>
      InboxCounters.empty;

  /// Stores the latest counts without persisting any message content.
  Future<void> saveCounters({
    required AuthSession session,
    required InboxCounters counters,
  }) async {}

  /// Loads an atomically reconciled, network-first Inbox projection.
  Future<InboxSnapshot> load({required AuthSession session});

  /// Emits connection state and realtime Inbox deltas. The default keeps
  /// simple/offline repository implementations source-compatible.
  Stream<InboxRealtimeEvent> watch({required AuthSession session}) =>
      const Stream<InboxRealtimeEvent>.empty();

  /// Requests a fresh realtime transport after an app/network lifecycle gap.
  /// Offline and test repositories may keep the default no-op behavior.
  void reconnectRealtime() {}

  /// Acknowledges the posts or thread activity represented by [item].
  Future<void> markRead({
    required AuthSession session,
    required InboxItem item,
  });
}
