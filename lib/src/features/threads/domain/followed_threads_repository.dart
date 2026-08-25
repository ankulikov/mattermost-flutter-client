import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/threads/domain/followed_thread.dart';

abstract interface class FollowedThreadsRepository {
  Future<FollowedThreadsPage> loadPage({
    required AuthSession session,
    required String teamId,
    String? before,
  });
}
