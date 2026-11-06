import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_channel_repository.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';

import 'support/fake_user_repository.dart';

void main() {
  test(
    'loads team first, groups channels, and resolves direct names',
    () async {
      final Uri serverUrl = Uri.parse('https://chat.example.com');
      final _FakeMattermostApi api = _FakeMattermostApi();
      final MattermostChannelRepository repository =
          MattermostChannelRepository(api: api, users: FakeUserRepository());
      final AuthSession session = AuthSession(
        serverUrl: serverUrl,
        userId: 'me',
        username: 'current',
      );

      final ChannelSidebarSnapshot snapshot = await repository.load(session);

      expect(api.calls.first, 'teams');
      expect(
        api.calls,
        containsAll(<String>[
          'channels:team-1',
          'memberships:team-1',
          'categories:team-1',
        ]),
      );
      expect(snapshot.team?.displayName, 'Example team');
      expect(snapshot.sections.first.displayName, 'Work');
      expect(
        snapshot.sections.first.channels.first.displayName,
        'Ada Lovelace',
      );
      expect(
        snapshot.sections.first.channels.first.profileImage?.userId,
        'ada',
      );
      expect(
        snapshot.sections.first.channels.first.profileImage?.updatedAt,
        99,
      );
      expect(snapshot.sections.first.channels.first.isUnread, isTrue);
      expect(snapshot.sections.first.channels.first.muted, isFalse);
    },
  );

  test(
    'channel actions use posts, notifications, and server categories',
    () async {
      final _FakeMattermostApi api = _FakeMattermostApi();
      final MattermostChannelRepository repository =
          MattermostChannelRepository(api: api, users: FakeUserRepository());
      final AuthSession session = AuthSession(
        serverUrl: Uri.parse('https://chat.example.com'),
        userId: 'me',
        username: 'current',
      );
      await repository.markChannelUnread(session, 'town-square');
      expect(api.unreadPostId, 'post-1');

      await repository.setChannelMuted(session, 'town-square', true);
      expect(api.mutedChannelId, 'town-square');

      await repository.setChannelFavorite(
        session,
        'team-1',
        const SidebarChannel(
          id: 'town-square',
          teamId: 'team-1',
          name: 'town-square',
          displayName: 'Town Square',
          kind: ChannelKind.publicChannel,
        ),
        true,
      );
      expect(api.movedCategoryId, 'favorites');
    },
  );

  test(
    'closing a direct conversation persists and hides it on reload',
    () async {
      final _FakeMattermostApi api = _FakeMattermostApi();
      final MattermostChannelRepository repository =
          MattermostChannelRepository(api: api, users: FakeUserRepository());
      final AuthSession session = AuthSession(
        serverUrl: Uri.parse('https://chat.example.com'),
        userId: 'me',
        username: 'current',
      );
      final SidebarChannel direct = (await repository.load(
        session,
      )).sections.first.channels.first;
      await repository.closeConversation(session, direct);
      expect(api.savedPreferences.single.category, 'direct_channel_show');
      expect(api.savedPreferences.single.value, 'false');
      final ChannelSidebarSnapshot reloaded = await repository.load(session);
      expect(
        reloaded.sections
            .expand((SidebarSection section) => section.channels)
            .any((SidebarChannel channel) => channel.id == direct.id),
        isFalse,
      );
    },
  );

  test(
    'leaving a channel removes its membership for the signed-in user',
    () async {
      final _FakeMattermostApi api = _FakeMattermostApi();
      final MattermostChannelRepository repository =
          MattermostChannelRepository(api: api, users: FakeUserRepository());
      final AuthSession session = AuthSession(
        serverUrl: Uri.parse('https://chat.example.com'),
        userId: 'me',
        username: 'current',
      );

      await repository.leaveChannel(
        session,
        const SidebarChannel(
          id: 'project',
          teamId: 'team-1',
          name: 'project',
          displayName: 'Project',
          kind: ChannelKind.publicChannel,
        ),
      );

      expect(api.leftChannelId, 'project');
      expect(api.leftUserId, 'me');
    },
  );
}

final class _FakeMattermostApi implements MattermostApi {
  String? unreadPostId;
  String? mutedChannelId;
  String? movedCategoryId;
  String? leftChannelId;
  String? leftUserId;
  final List<MattermostPreferenceDto> savedPreferences =
      <MattermostPreferenceDto>[];

  @override
  Future<void> markPostUnread({
    required String userId,
    required String postId,
  }) async => unreadPostId = postId;

  @override
  Future<void> setChannelNotificationsMuted({
    required String userId,
    required String channelId,
    required bool muted,
  }) async => mutedChannelId = channelId;

  @override
  Future<void> moveChannelToSidebarCategory({
    required String userId,
    required String teamId,
    required String channelId,
    required String categoryId,
  }) async => movedCategoryId = categoryId;

  @override
  Future<void> leaveChannel({
    required String channelId,
    required String userId,
  }) async {
    leftChannelId = channelId;
    leftUserId = userId;
  }

  @override
  Future<void> savePreferences({
    required String userId,
    required List<MattermostPreferenceDto> preferences,
  }) async => savedPreferences.addAll(preferences);

  @override
  Future<List<MattermostPreferenceDto>> getPreferencesByCategory({
    required String userId,
    required String category,
  }) async => savedPreferences
      .where((MattermostPreferenceDto value) => value.category == category)
      .toList(growable: false);
  @override
  Future<List<MattermostUserDto>> getUsersByUsernames(List<String> usernames) =>
      throw UnimplementedError();

  @override
  Future<void> saveReaction({
    required String userId,
    required String postId,
    required String emojiName,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteReaction({
    required String userId,
    required String postId,
    required String emojiName,
  }) => throw UnimplementedError();

  @override
  Future<MattermostChannelDto> createDirectChannel({
    required String currentUserId,
    required String otherUserId,
  }) => throw UnimplementedError();

  @override
  Future<MattermostUserStatusDto> getUserStatus(String userId) =>
      throw UnimplementedError();

  @override
  Future<MattermostUserDto> getUserById(String userId) =>
      throw UnimplementedError();

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
  Future<MattermostEmojiDto> getCustomEmojiByName(String name) =>
      throw UnimplementedError();

  @override
  Future<MattermostImageDto> getCustomEmojiImage(String emojiId) =>
      throw UnimplementedError();

  @override
  Future<MattermostFileContentDto> getFile(String fileId) =>
      throw UnimplementedError();

  @override
  Future<MattermostFileContentDto> getFilePreview(String fileId) =>
      throw UnimplementedError();

  @override
  Future<MattermostFileContentDto> getFileThumbnail(String fileId) =>
      throw UnimplementedError();

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
        MattermostChannelCategoryDto(
          id: 'favorites',
          userId: 'me',
          teamId: 'team-1',
          type: 'favorites',
          displayName: 'Favorites',
          sorting: 'manual',
          channelIds: <String>[],
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
        totalMessageCount: 2,
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
  Future<List<MattermostChannelMemberDto>> getChannelMembersForUser({
    required String userId,
    required String teamId,
  }) async {
    calls.add('memberships:$teamId');
    return const <MattermostChannelMemberDto>[
      MattermostChannelMemberDto(
        channelId: 'direct-1',
        userId: 'me',
        msgCount: 1,
        notifyProps: MattermostChannelNotifyPropsDto(markUnread: 'all'),
      ),
      MattermostChannelMemberDto(channelId: 'town-square', userId: 'me'),
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
  }) async => const MattermostPostListDto(
    order: <String>['post-1'],
    posts: <String, MattermostPostDto>{},
    nextPostId: '',
    previousPostId: '',
    hasNext: false,
  );

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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
