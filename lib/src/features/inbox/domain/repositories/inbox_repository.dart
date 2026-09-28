import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_completeness.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';

abstract class InboxRepository {
  const InboxRepository();

  /// Loads an atomically reconciled, network-first Inbox projection.
  Future<InboxSnapshot> load({required AuthSession session});

  /// Rebuilds the server-backed Postponed queue while retaining the current
  /// volatile Inbox projection. Implementations that do not have a scoped
  /// source may fall back to a complete snapshot.
  Future<InboxSnapshot> reloadPostponed({
    required AuthSession session,
    required InboxSnapshot current,
  }) => load(session: session);

  /// Retries one independently loaded source while retaining [current] until
  /// the replacement is authoritative.
  ///
  /// Implementations can override this for a source that has a narrower
  /// server-side reconciliation. The default deliberately preserves the
  /// existing compatibility contract: only Postponed has a dedicated reload;
  /// other sources fall back to one atomic network-first snapshot.
  Future<InboxSnapshot> reloadSource({
    required AuthSession session,
    required InboxSnapshot current,
    required InboxSourceScope scope,
  }) => switch (scope) {
    InboxSourceScope.postponed => reloadPostponed(
      session: session,
      current: current,
    ),
    InboxSourceScope.followedThreads ||
    InboxSourceScope.unreadChannelPosts => load(session: session),
  };

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
}
