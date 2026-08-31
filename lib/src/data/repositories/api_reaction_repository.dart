import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/repositories/reaction_repository.dart';

final class ApiReactionRepository implements ReactionRepository {
  const ApiReactionRepository({required MattermostApi api}) : _api = api;

  final MattermostApi _api;

  @override
  Future<void> add({
    required AuthSession session,
    required String postId,
    required String emojiName,
  }) => _api.saveReaction(
    userId: session.userId,
    postId: postId,
    emojiName: emojiName,
  );

  @override
  Future<void> remove({
    required AuthSession session,
    required String postId,
    required String emojiName,
  }) => _api.deleteReaction(
    userId: session.userId,
    postId: postId,
    emojiName: emojiName,
  );
}
