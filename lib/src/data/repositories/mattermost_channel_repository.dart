import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/channel_sidebar_mapper.dart';
import 'package:mattermost_flutter/src/data/mappers/dialog_display_name_mapper.dart';
import 'package:mattermost_flutter/src/data/mappers/user_mapper.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/channel_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_repository.dart';

final class MattermostChannelRepository implements ChannelRepository {
  const MattermostChannelRepository({
    required MattermostApi api,
    required UserRepository users,
  }) : _api = api,
       _users = users;

  final MattermostApi _api;
  final UserRepository _users;

  @override
  Future<ChannelSidebarSnapshot> load(AuthSession session) async {
    final List<MattermostTeamDto> teams = await _api.getTeamsForCurrentUser();
    if (teams.isEmpty) return const ChannelSidebarSnapshot();
    final SidebarTeam team = mapTeam(teams.first);
    final Future<List<MattermostChannelDto>> channelsFuture = _api
        .getChannelsForUser(userId: session.userId, teamId: team.id);
    final Future<MattermostChannelCategoriesDto> categoriesFuture = _api
        .getChannelCategories(userId: session.userId, teamId: team.id);
    final List<MattermostChannelDto> rawChannels = await channelsFuture;
    final MattermostChannelCategoriesDto categoryResponse =
        await categoriesFuture;
    List<SidebarChannel> channels = rawChannels
        .map(mapChannel)
        .toList(growable: false);
    try {
      channels = await _resolveDialogNames(
        api: _api,
        users: _users,
        currentUserId: session.userId,
        channels: channels,
      );
    } on Object {
      // Participant profiles are an enhancement. Channel navigation remains
      // usable with the server-provided channel name when profile lookup fails.
    }
    return ChannelSidebarSnapshot(
      team: team,
      sections: mapSections(
        channels: channels,
        categories: categoryResponse.categories,
        categoryOrder: categoryResponse.order,
      ),
    );
  }

  @override
  Future<SidebarChannel> openDirectMessage({
    required String currentUserId,
    required String otherUserId,
    required String otherUserDisplayName,
  }) async {
    final MattermostChannelDto dto = await _api.createDirectChannel(
      currentUserId: currentUserId,
      otherUserId: otherUserId,
    );
    return mapChannel(dto).withDisplayName(otherUserDisplayName);
  }

  Future<List<SidebarChannel>> _resolveDialogNames({
    required MattermostApi api,
    required UserRepository users,
    required String currentUserId,
    required List<SidebarChannel> channels,
  }) async {
    final List<SidebarChannel> directChannels = channels
        .where((SidebarChannel item) => item.kind == ChannelKind.directMessage)
        .toList(growable: false);
    final List<SidebarChannel> groupChannels = channels
        .where((SidebarChannel item) => item.kind == ChannelKind.groupMessage)
        .toList(growable: false);
    final Set<String> directUserIds = directChannels
        .map(
          (SidebarChannel item) => directParticipantId(
            channelName: item.name,
            currentUserId: currentUserId,
          ),
        )
        .whereType<String>()
        .toSet();
    final Future<List<UserSummary>> directUsersFuture = users.getUsers(
      directUserIds.toList(growable: false),
    );
    final Future<MattermostGroupChannelUsersDto> groupUsersFuture = api
        .getUsersForGroupChannels(
          groupChannels
              .map((SidebarChannel item) => item.id)
              .toList(growable: false),
        );
    final List<UserSummary> directUsers = await directUsersFuture;
    final MattermostGroupChannelUsersDto groupUsers = await groupUsersFuture;
    final Map<String, UserSummary> directUsersById = <String, UserSummary>{
      for (final UserSummary user in directUsers)
        if (user.id.isNotEmpty) user.id: user,
    };

    return resolveDialogDisplayNames(
      channels: channels,
      currentUserId: currentUserId,
      directUsersById: directUsersById,
      groupUsersByChannelId: groupUsers.usersByChannelId.map(
        (String channelId, List<MattermostUserDto> users) =>
            MapEntry<String, List<UserSummary>>(
              channelId,
              users.map(mapUserSummary).toList(growable: false),
            ),
      ),
    );
  }
}
