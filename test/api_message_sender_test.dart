import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/messages/data/api_message_sender.dart';
import 'package:mattermost_flutter/src/features/messages/data/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message.dart';

void main() {
  test('sends a reply and maps the authoritative response', () async {
    final _CreatePostApi api = _CreatePostApi();
    final ApiMessageSender sender = ApiMessageSender(
      api: api,
      messageMapper: const MattermostMessageMapper(),
    );
    final AuthSession session = AuthSession(
      serverUrl: Uri.parse('https://chat.example.com'),
      userId: 'me',
      username: 'current-user',
    );

    final ChannelPost sent = await sender.sendText(
      session: session,
      channelId: 'channel-1',
      rootPostId: 'root-1',
      message: 'A reply',
      pendingPostId: 'pending-1',
    );

    expect(api.request?.channelId, 'channel-1');
    expect(api.request?.rootId, 'root-1');
    expect(api.request?.message, 'A reply');
    expect(api.request?.pendingPostId, 'pending-1');
    expect(sent.id, 'post-1');
    expect(sent.rootId, 'root-1');
    expect(sent.author.displayName, 'current-user');
  });
}

final class _CreatePostApi extends Fake implements MattermostApi {
  MattermostCreatePostRequestDto? request;

  @override
  Future<MattermostPostDto> createPost(
    MattermostCreatePostRequestDto post,
  ) async {
    request = post;
    return MattermostPostDto(
      id: 'post-1',
      userId: 'me',
      channelId: post.channelId,
      message: post.message,
      rootId: post.rootId,
      pendingPostId: post.pendingPostId,
      createAt: 1000,
    );
  }
}
