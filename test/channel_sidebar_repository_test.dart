import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/core/database/app_database.dart' as db;
import 'package:mattermost_flutter/src/features/auth/data/credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/channels/data/api_channel_sidebar_repository.dart';
import 'package:mattermost_flutter/src/features/channels/data/channel_sidebar_store.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';

void main() {
  test(
    'loads team first, groups channels, and resolves direct names',
    () async {
      final Uri serverUrl = Uri.parse('https://chat.example.com');
      final _FakeMattermostApi api = _FakeMattermostApi();
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final ApiChannelSidebarRepository repository =
          ApiChannelSidebarRepository(
            credentialStore: _FakeCredentialStore(serverUrl),
            store: ChannelSidebarStore(database),
            clientFactory: _FakeApiFactory(api),
          );
      final AuthSession session = AuthSession(
        serverUrl: serverUrl,
        userId: 'me',
        username: 'current',
      );

      await repository.refresh(session);
      final ChannelSidebarSnapshot snapshot = await repository
          .watch(session.accountId)
          .first;

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

final class _FakeCredentialStore implements CredentialStore {
  const _FakeCredentialStore(this.serverUrl);

  final Uri serverUrl;

  @override
  Future<void> clear() async {}

  @override
  Future<({Uri serverUrl, String token})?> read() async =>
      (serverUrl: serverUrl, token: 'token');

  @override
  Future<void> save({required Uri serverUrl, required String token}) async {}
}

final class _FakeApiFactory implements MattermostApiFactory {
  const _FakeApiFactory(this.api);

  final MattermostApi api;

  @override
  MattermostApi create({required Uri serverUrl, required String token}) => api;
}

final class _FakeMattermostApi implements MattermostApi {
  final List<String> calls = <String>[];

  @override
  Future<MattermostPostListDto> getPostThread({
    required String rootPostId,
    int perPage = 60,
    String? fromPost,
    int? fromCreateAt,
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
