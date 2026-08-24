import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/threads/domain/message_thread.dart';

abstract interface class ThreadRepository {
  Stream<MessageThread> watch({
    required String accountId,
    required String rootPostId,
  });

  Future<MessageThread> read({
    required String accountId,
    required String rootPostId,
  });

  Future<void> refresh({
    required AuthSession session,
    required String rootPostId,
  });
}
