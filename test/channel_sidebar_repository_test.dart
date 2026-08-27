import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/channels/data/api_channel_sidebar_repository.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';

void main() {
  test(
    'loads team first, groups channels, and resolves direct names',
    () async {
      final Uri serverUrl = Uri.parse('https://chat.example.com');
      final _FakeMattermostApi api = _FakeMattermostApi();
      final ApiChannelSidebarRepository repository =
          ApiChannelSidebarRepository(api: api);
      final AuthSession session = AuthSession(
        serverUrl: serverUrl,
        userId: 'me',
        username: 'current',
      );

      final ChannelSidebarSnapshot snapshot = await repository.load(session);

      expect(api.calls.first, 'teams');
      expect(
        api.calls,
        containsAll(<String>['channels:team-1', 'categories:team-1']),
      );
      expect(snapshot.team?.displayName, 'Example team');
      expect(snapshot.sections.first.displayName, 'Work');
      expect(
        snapshot.sections.first.channels.first.displayName,
        'Ada Lovelace',
      );
      expect(snapshot.isRefreshing, isFalse);
      expect(snapshot.refreshFailed, isFalse);
    },
  );
}

final class _FakeMattermostApi implements MattermostApi {
  @override
  Future<void> updateThreadRead({
    required String userId,
    required String teamId,
    required String threadId,
    required int timestamp,
  }) => throw UnimplementedError();

  @override
  Future<MattermostPostDto> createPost(MattermostCreatePostRequestDto post) =>
      throw UnimplementedError();

  @override
  Future<MattermostImageDto> getUserProfileImage({
    required String userId,
    int lastPictureUpdate = 0,
  }) => throw UnimplementedError();

  @override
  Future<MattermostUserThreadsDto> getUserThreads({
    required String userId,
    required String teamId,
    int perPage = 60,
    String? before,
    bool extended = true,
    bool unread = false,
  }) => throw UnimplementedError();

  final List<String> calls = <String>[];

  @override
  Future<MattermostPostListDto> getPostThread({
    required String rootPostId,
    int perPage = 60,
    String? fromPost,
    int? fromCreateAt,
    PostThreadDirection direction = PostThreadDirection.up,
  }) => throw UnimplementedError();

  @override
  Future<MattermostChannelCategoriesDto> getChannelCategories({
    required String userId,
    required String teamId,
  }) async {
    calls.add('categories:$teamId');
    return const MattermostChannelCategoriesDto(
      categories: <MattermostChannelCategoryDto>[
        MattermostChannelCategoryDto(
          id: 'category-1',
          userId: 'me',
          teamId: 'team-1',
          type: 'custom',
          displayName: 'Work',
          sorting: 'manual',
          channelIds: <String>['direct-1', 'town-square'],
          muted: false,
        ),
      ],
      order: <String>['category-1'],
    );
  }

  @override
  Future<List<MattermostChannelDto>> getChannelsForUser({
    required String userId,
    required String teamId,
    String? etag,
  }) async {
    calls.add('channels:$teamId');
    return <MattermostChannelDto>[
      const MattermostChannelDto(
        id: 'direct-1',
        teamId: '',
        name: 'me__ada',
        displayName: '',
        type: 'D',
      ),
      MattermostChannelDto(
        id: 'town-square',
        teamId: teamId,
        name: 'town-square',
        displayName: 'Town Square',
        type: 'O',
      ),
    ];
  }

  @override
  Future<MattermostUserDto> getCurrentUser() => throw UnimplementedError();

  @override
  Future<MattermostPostListDto> getPostsForChannel({
    required String channelId,
    int page = 0,
    int perPage = 60,
    String? etag,
  }) => throw UnimplementedError();

  @override
  Future<MattermostPostListDto> getPostsBefore({
    required String channelId,
    required String postId,
    int page = 0,
    int perPage = 60,
  }) => throw UnimplementedError();

  @override
  Future<MattermostPostListDto> getPostsSince({
    required String channelId,
    required int since,
  }) => throw UnimplementedError();

  @override
  Future<List<MattermostTeamDto>> getTeamsForCurrentUser() async {
    calls.add('teams');
    return const <MattermostTeamDto>[
      MattermostTeamDto(
        id: 'team-1',
        name: 'example',
        displayName: 'Example team',
      ),
    ];
  }

  @override
  Future<List<MattermostUserDto>> getUsersByIds(List<String> userIds) async {
    calls.add('users:${userIds.join(',')}');
    return const <MattermostUserDto>[
      MattermostUserDto(
        id: 'ada',
        username: 'ada',
        firstName: 'Ada',
        lastName: 'Lovelace',
      ),
    ];
  }

  @override
  Future<MattermostGroupChannelUsersDto> getUsersForGroupChannels(
    List<String> channelIds,
  ) async {
    calls.add('groups:${channelIds.join(',')}');
    return const MattermostGroupChannelUsersDto(
      usersByChannelId: <String, List<MattermostUserDto>>{},
    );
  }
}
