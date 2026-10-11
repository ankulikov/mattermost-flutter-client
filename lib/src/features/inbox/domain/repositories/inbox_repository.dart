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

  /// Advances the server read boundary represented by [item].
  Future<void> markRead({
    required AuthSession session,
    required InboxItem item,
  });

  /// Marks a followed thread and its root post read as one Inbox action.
  ///
  /// When [preserveOtherChannelRoots] is true, implementations must retain the
  /// containing channel's other unread roots and suppress only this root.
  Future<void> markThreadRead({
    required AuthSession session,
    required ThreadInboxItem item,
    required bool preserveOtherChannelRoots,
  }) => markRead(session: session, item: item);

  /// Dismisses only [item] without advancing the containing channel boundary.
  ///
  /// Implementations without individual-post persistence retain their previous
  /// whole-channel behavior.
  Future<void> markPostViewed({
    required AuthSession session,
    required ChannelPostInboxItem item,
  }) => markRead(session: session, item: item);
}
