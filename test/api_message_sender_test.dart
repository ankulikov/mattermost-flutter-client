import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_post_repository.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';

import 'support/fake_user_repository.dart';

void main() {
  test('sends a reply and maps the authoritative response', () async {
    final _CreatePostApi api = _CreatePostApi();
    final MattermostPostRepository sender = MattermostPostRepository(
      api: api,
      messageMapper: const MattermostMessageMapper(),
      users: FakeUserRepository(),
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
