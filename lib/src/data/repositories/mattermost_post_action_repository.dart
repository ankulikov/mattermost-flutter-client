import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/post_action.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/message_mapper.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_action_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_repository.dart';

final class MattermostPostActionRepository implements PostActionRepository {
  const MattermostPostActionRepository({
    required MattermostApi api,
    required MessageMapper<MattermostPostDto, UserSummary> messageMapper,
    required UserRepository users,
  }) : _api = api,
       _messageMapper = messageMapper,
       _users = users;

  final MattermostApi _api;
  final MessageMapper<MattermostPostDto, UserSummary> _messageMapper;
  final UserRepository _users;

  @override
  Future<PostActionResult> execute({
    required AuthSession session,
    required String postId,
    required String actionId,
    RichAttachmentActionToken? token,
    String? selectedOption,
  }) async {
    final MattermostPostActionResponseDto response = await _api
        .executePostAction(
          postId: postId,
          actionId: actionId,
          request: MattermostPostActionRequestDto(
            cookie: token?.value,
            selectedOption: selectedOption,
          ),
        );
    final MattermostPostDto refreshed = await _api.getPost(postId);
    final List<UserSummary> users = await _users.getUsers(<String>[
      refreshed.userId,
    ], freshness: UserFreshness.fresh);
    final ChannelPost updatedPost = _messageMapper
        .map(
          posts: <MattermostPostDto>[refreshed],
          users: users,
          currentUserId: session.userId,
          includeDeleted: true,
        )
        .single;
    return PostActionResult(
      updatedPost: updatedPost,
      gotoLocation: response.gotoLocation,
    );
  }
}
