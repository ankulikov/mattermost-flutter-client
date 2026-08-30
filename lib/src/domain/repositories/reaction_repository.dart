import 'package:mattermost_flutter/src/domain/models/auth_session.dart';

abstract interface class ReactionRepository {
  Future<void> add({
    required AuthSession session,
    required String postId,
    required String emojiName,
  });

  Future<void> remove({
    required AuthSession session,
    required String postId,
    required String emojiName,
  });
}
