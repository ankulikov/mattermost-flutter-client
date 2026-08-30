import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/message_thread.dart';

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
