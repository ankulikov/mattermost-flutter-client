import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/channel_members/data/mattermost_channel_members_repository.dart';
import 'package:mattermost_flutter/src/features/channel_members/domain/channel_member.dart';

import '../../../support/fake_user_repository.dart';

void main() {
  test('loads count from channel statistics', () async {
    final MattermostChannelMembersRepository repository =
        MattermostChannelMembersRepository(
          api: _ChannelMembersApi(),
          users: FakeUserRepository(),
        );

    expect(await repository.getCount('channel-1'), 2);
  });

  test(
    'resolves paged memberships through the shared user repository',
    () async {
      final FakeUserRepository users = FakeUserRepository();
      final MattermostChannelMembersRepository repository =
          MattermostChannelMembersRepository(
            api: _ChannelMembersApi(),
            users: users,
          );

      final ChannelMembersPage page = await repository.loadPage(
        channelId: 'channel-1',
        page: 0,
        perPage: 2,
      );

      expect(users.requestedIdBatches, <List<String>>[
        <String>['ada', 'grace'],
      ]);
      expect(page.members.map((member) => member.user.fullName), <String>[
        'Ada Lovelace',
        'Grace Hopper',
      ]);
      expect(page.members.first.isChannelAdmin, isTrue);
      expect(page.members.last.isChannelAdmin, isFalse);
      expect(page.hasMore, isTrue);
    },
  );
}

final class _ChannelMembersApi implements MattermostChannelMembersApi {
  @override
  Future<List<MattermostChannelMemberDto>> getChannelMembers({
    required String channelId,
    int page = 0,
    int perPage = 60,
  }) async => const <MattermostChannelMemberDto>[
    MattermostChannelMemberDto(
      channelId: 'channel-1',
      userId: 'ada',
      roles: 'channel_user channel_admin',
    ),
    MattermostChannelMemberDto(
      channelId: 'channel-1',
      userId: 'grace',
      roles: 'channel_user',
    ),
  ];

  @override
  Future<MattermostChannelStatsDto> getChannelStats(String channelId) async =>
      const MattermostChannelStatsDto(channelId: 'channel-1', memberCount: 2);
}
