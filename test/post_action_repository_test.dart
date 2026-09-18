import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_post_action_repository.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';

import 'support/fake_user_repository.dart';

void main() {
  test(
    'dispatches with its opaque cookie then maps the refreshed post',
    () async {
      final _ActionApi api = _ActionApi();
      final MattermostPostActionRepository repository =
          MattermostPostActionRepository(
            api: api,
            messageMapper: const MattermostMessageMapper(),
            users: FakeUserRepository(),
          );

      final result = await repository.execute(
        session: AuthSession(
          serverUrl: Uri.parse('https://chat.example.com'),
          userId: 'me',
          username: 'me',
        ),
        postId: 'post-1',
        actionId: 'approve',
        token: const RichAttachmentActionToken('encrypted-cookie'),
        selectedOption: 'yes',
      );

      expect(api.postId, 'post-1');
      expect(api.actionId, 'approve');
      expect(api.request?.cookie, 'encrypted-cookie');
      expect(api.request?.selectedOption, 'yes');
      expect(api.refreshedPostId, 'post-1');
      expect(result.updatedPost.message, 'Updated by integration');
      expect(result.gotoLocation, 'https://chat.example.com/team/pl/next');
    },
  );

  test(
    'dispatches a legacy action when the server did not include a cookie',
    () async {
      final _ActionApi api = _ActionApi();
      final MattermostPostActionRepository repository =
          MattermostPostActionRepository(
            api: api,
            messageMapper: const MattermostMessageMapper(),
            users: FakeUserRepository(),
          );

      await repository.execute(
        session: AuthSession(
          serverUrl: Uri.parse('https://chat.example.com'),
          userId: 'me',
          username: 'me',
        ),
        postId: 'post-1',
        actionId: 'approve',
        token: null,
      );

      expect(api.request?.cookie, isNull);
      expect(api.request?.toJson(), isEmpty);
    },
  );
}

final class _ActionApi extends Fake implements MattermostApi {
  String? postId;
  String? actionId;
  String? refreshedPostId;
  MattermostPostActionRequestDto? request;

  @override
  Future<MattermostPostActionResponseDto> executePostAction({
    required String postId,
    required String actionId,
    required MattermostPostActionRequestDto request,
  }) async {
    this.postId = postId;
    this.actionId = actionId;
    this.request = request;
    return const MattermostPostActionResponseDto(
      status: 'OK',
      gotoLocation: 'https://chat.example.com/team/pl/next',
    );
  }

  @override
  Future<MattermostPostDto> getPost(String postId) async {
    refreshedPostId = postId;
    return const MattermostPostDto(
      id: 'post-1',
      userId: 'ada',
      channelId: 'channel-1',
      message: 'Updated by integration',
      createAt: 1,
    );
  }
}
