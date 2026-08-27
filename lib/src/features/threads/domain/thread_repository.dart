import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/threads/domain/message_thread.dart';

abstract interface class ThreadRepository {
  Future<MessageThread> load({
    required AuthSession session,
    required String rootPostId,
  });

  Future<void> markRead({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
    required DateTime timestamp,
  });
}
