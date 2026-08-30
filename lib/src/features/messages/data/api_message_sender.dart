import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message_mapper.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message_sender.dart';

final class ApiMessageSender implements MessageSender {
  const ApiMessageSender({
    required MattermostApi api,
    required MessageMapper<MattermostPostDto, UserSummary> messageMapper,
  }) : _api = api,
       _messageMapper = messageMapper;

  final MattermostApi _api;
  final MessageMapper<MattermostPostDto, UserSummary> _messageMapper;

  @override
  Future<ChannelPost> sendText({
    required AuthSession session,
    required String channelId,
    required String message,
    required String pendingPostId,
    String rootPostId = '',
  }) async {
    final MattermostPostDto post = await _api.createPost(
      MattermostCreatePostRequestDto(
        channelId: channelId,
        message: message,
        pendingPostId: pendingPostId,
        rootId: rootPostId,
      ),
    );
    final List<ChannelPost> mapped = _messageMapper.map(
      posts: <MattermostPostDto>[post],
      users: <UserSummary>[
        UserSummary(
          id: session.userId,
          username: session.username,
          firstName: '',
          lastName: '',
          nickname: '',
          position: '',
          email: '',
        ),
      ],
      currentUserId: session.userId,
      includeDeleted: true,
    );
    if (mapped case <ChannelPost>[final ChannelPost result]) return result;
    throw const FormatException('Create post response could not be mapped');
  }
}
