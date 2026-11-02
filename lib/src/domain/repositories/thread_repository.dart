import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/message_thread.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';

abstract class ThreadRepository {
  const ThreadRepository();

  Future<MessageThread> load({
    required AuthSession session,
    required String rootPostId,
  }) => throw UnimplementedError();

  Future<void> markRead({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
    required DateTime timestamp,
  }) => throw UnimplementedError();

  Future<FollowedThreadsPage> loadFollowed({
    required AuthSession session,
    required String teamId,
    String? before,
  }) => throw UnimplementedError();

  /// Whether the current user follows this CRT thread.
  Future<bool> isFollowing({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
  }) async => false;

  Future<void> follow({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
  }) => throw UnimplementedError();

  Future<void> unfollow({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
  }) => throw UnimplementedError();
}

/// Optional realtime capability for the followed-thread summary.
///
/// Thread socket payloads are deliberately not exposed to presentation: a
/// refresh from the followed-threads endpoint is the authoritative source for
/// its aggregate unread counters.
abstract interface class FollowedThreadsRealtimeRepository {
  Stream<FollowedThreadsRealtimeEvent> watchFollowedThreads({
    required AuthSession session,
    required String teamId,
  });
}

sealed class FollowedThreadsRealtimeEvent {
  const FollowedThreadsRealtimeEvent();
}

/// The followed-thread projection, including unread totals, must be reloaded.
final class FollowedThreadsRefreshRequired
    extends FollowedThreadsRealtimeEvent {
  const FollowedThreadsRefreshRequired();
}
