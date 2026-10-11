import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_repository.dart';
import 'package:mattermost_flutter/src/features/channel_members/domain/channel_member.dart';
import 'package:mattermost_flutter/src/features/channel_members/domain/channel_members_repository.dart';

final class MattermostChannelMembersRepository
    implements ChannelMembersRepository {
  const MattermostChannelMembersRepository({
    required MattermostChannelMembersApi api,
    required UserRepository users,
  }) : _api = api,
       _users = users;

  final MattermostChannelMembersApi _api;
  final UserRepository _users;

  @override
  Future<int> getCount(String channelId) async =>
      (await _api.getChannelStats(channelId)).memberCount;

  @override
  Future<ChannelMembersPage> loadPage({
    required String channelId,
    required int page,
    required int perPage,
  }) async {
    final List<MattermostChannelMemberDto> memberships = await _api
        .getChannelMembers(channelId: channelId, page: page, perPage: perPage);
    final List<String> userIds = memberships
        .map((MattermostChannelMemberDto member) => member.userId)
        .where((String id) => id.isNotEmpty)
        .toList(growable: false);
    final List<UserSummary> users = await _users.getUsers(userIds);
    final Map<String, UserSummary> usersById = <String, UserSummary>{
      for (final UserSummary user in users) user.id: user,
    };
    return ChannelMembersPage(
      members: List<ChannelMember>.unmodifiable(
        memberships.map((MattermostChannelMemberDto membership) {
          final UserSummary? user = usersById[membership.userId];
          if (user == null) return null;
          return ChannelMember(
            user: user,
            isChannelAdmin: membership.roles
                .split(' ')
                .contains('channel_admin'),
          );
        }).whereType<ChannelMember>(),
      ),
      hasMore: memberships.length == perPage,
    );
  }
}
