import 'dart:collection';

import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/channel_sidebar_mapper.dart';
import 'package:mattermost_flutter/src/data/mappers/dialog_display_name_mapper.dart';
import 'package:mattermost_flutter/src/data/mappers/user_mapper.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';

/// Immutable, shared REST context for one Inbox snapshot.
///
/// Snapshot sources must use this context instead of loading the current user,
/// teams, channels, or memberships themselves. Dialog display names are also
/// resolved once here so every source projects the same channel identity.
final class InboxSnapshotContext {
  InboxSnapshotContext({
    required this.currentUser,
    required Iterable<MattermostTeamDto> teams,
    required Map<String, MattermostChannelDto> rawChannels,
    required Map<String, MattermostChannelMemberDto> members,
    required Map<String, SidebarChannel> channels,
  }) : teams = UnmodifiableListView<MattermostTeamDto>(teams.toList()),
       rawChannels = UnmodifiableMapView<String, MattermostChannelDto>(
         Map<String, MattermostChannelDto>.of(rawChannels),
       ),
       members = UnmodifiableMapView<String, MattermostChannelMemberDto>(
         Map<String, MattermostChannelMemberDto>.of(members),
       ),
       channels = UnmodifiableMapView<String, SidebarChannel>(
         Map<String, SidebarChannel>.of(channels),
       );

  final MattermostUserDto currentUser;
  final List<MattermostTeamDto> teams;
  final Map<String, MattermostChannelDto> rawChannels;
  final Map<String, MattermostChannelMemberDto> members;
  final Map<String, SidebarChannel> channels;
}

/// Loads the non-source-specific part of a network-first Inbox snapshot once.
final class InboxContextLoader {
  InboxContextLoader({required MattermostApi api}) : _api = api;

  static const int _maxTeamConcurrency = 4;
  static const int _dialogLookupBatchSize = 100;

  final MattermostApi _api;

  Future<InboxSnapshotContext> load({required AuthSession session}) async {
    final MattermostUserDto currentUser = await _api.getCurrentUser();
    final List<MattermostTeamDto> teams = await _api.getTeamsForCurrentUser();
    final List<_TeamChannels> teamChannels = await _loadTeamChannels(
      teams: teams,
      userId: session.userId,
    );
    final Map<String, MattermostChannelDto> rawChannels =
        <String, MattermostChannelDto>{};
    final Map<String, MattermostChannelMemberDto> members =
        <String, MattermostChannelMemberDto>{};
    for (final _TeamChannels snapshot in teamChannels) {
      for (final MattermostChannelDto channel in snapshot.channels) {
        rawChannels.putIfAbsent(channel.id, () => channel);
      }
      for (final MattermostChannelMemberDto member in snapshot.members) {
        members.putIfAbsent(member.channelId, () => member);
      }
    }
    return InboxSnapshotContext(
      currentUser: currentUser,
      teams: teams,
      rawChannels: rawChannels,
      members: members,
      channels: await _resolveKnownChannels(
        rawChannels: rawChannels,
        currentUserId: session.userId,
      ),
    );
  }

  Future<List<_TeamChannels>> _loadTeamChannels({
    required List<MattermostTeamDto> teams,
    required String userId,
  }) async {
    final List<_TeamChannels> result = <_TeamChannels>[];
    for (var start = 0; start < teams.length; start += _maxTeamConcurrency) {
      final List<MattermostTeamDto> batch = teams.sublist(
        start,
        start + _maxTeamConcurrency > teams.length
            ? teams.length
            : start + _maxTeamConcurrency,
      );
      result.addAll(
        await Future.wait(
          batch.map(
            (MattermostTeamDto team) async => _TeamChannels(
              channels: await _api.getChannelsForUser(
                userId: userId,
                teamId: team.id,
              ),
              members: await _api.getChannelMembersForUser(
                userId: userId,
                teamId: team.id,
              ),
            ),
          ),
        ),
      );
    }
    return result;
  }

  Future<Map<String, SidebarChannel>> _resolveKnownChannels({
    required Map<String, MattermostChannelDto> rawChannels,
    required String currentUserId,
  }) async {
    final List<SidebarChannel> channels = rawChannels.values
        .map(_mapKnownChannel)
        .whereType<SidebarChannel>()
        .toList(growable: false);
    final Set<String> directParticipantIds = channels
        .where(
          (SidebarChannel channel) => channel.kind == ChannelKind.directMessage,
        )
        .map(
          (SidebarChannel channel) => directParticipantId(
            channelName: channel.name,
            currentUserId: currentUserId,
          ),
        )
        .whereType<String>()
        .toSet();
    final List<SidebarChannel> groupChannels = channels
        .where(
          (SidebarChannel channel) => channel.kind == ChannelKind.groupMessage,
        )
        .toList(growable: false);
    try {
      final List<MattermostUserDto> directUsers = await _loadDirectUsers(
        directParticipantIds,
      );
      final MattermostGroupChannelUsersDto groupUsers = await _loadGroupUsers(
        groupChannels,
      );
      final List<SidebarChannel> resolved = resolveDialogDisplayNames(
        channels: channels,
        currentUserId: currentUserId,
        directUsersById: <String, UserSummary>{
          for (final MattermostUserDto user in directUsers)
            if (user.id.isNotEmpty) user.id: mapUserSummary(user),
        },
        groupUsersByChannelId: groupUsers.usersByChannelId.map(
          (String channelId, List<MattermostUserDto> users) =>
              MapEntry<String, List<UserSummary>>(
                channelId,
                users.map(mapUserSummary).toList(growable: false),
              ),
        ),
      );
      return <String, SidebarChannel>{
        for (final SidebarChannel channel in resolved) channel.id: channel,
      };
    } on Object {
      return <String, SidebarChannel>{
        for (final SidebarChannel channel in channels) channel.id: channel,
      };
    }
  }

  Future<List<MattermostUserDto>> _loadDirectUsers(
    Set<String> participantIds,
  ) async {
    final List<String> ids = participantIds.toList(growable: false);
    final List<MattermostUserDto> result = <MattermostUserDto>[];
    for (var start = 0; start < ids.length; start += _dialogLookupBatchSize) {
      result.addAll(
        await _api.getUsersByIds(
          ids.sublist(
            start,
            start + _dialogLookupBatchSize > ids.length
                ? ids.length
                : start + _dialogLookupBatchSize,
          ),
        ),
      );
    }
    return result;
  }

  Future<MattermostGroupChannelUsersDto> _loadGroupUsers(
    List<SidebarChannel> groupChannels,
  ) async {
    final Map<String, List<MattermostUserDto>> usersByChannelId =
        <String, List<MattermostUserDto>>{};
    for (
      var start = 0;
      start < groupChannels.length;
      start += _dialogLookupBatchSize
    ) {
      final MattermostGroupChannelUsersDto batch = await _api
          .getUsersForGroupChannels(
            groupChannels
                .sublist(
                  start,
                  start + _dialogLookupBatchSize > groupChannels.length
                      ? groupChannels.length
                      : start + _dialogLookupBatchSize,
                )
                .map((SidebarChannel channel) => channel.id)
                .toList(growable: false),
          );
      usersByChannelId.addAll(batch.usersByChannelId);
    }
    return MattermostGroupChannelUsersDto(usersByChannelId: usersByChannelId);
  }

  SidebarChannel? _mapKnownChannel(MattermostChannelDto channel) {
    try {
      return mapChannel(channel);
    } on FormatException {
      return null;
    }
  }
}

final class _TeamChannels {
  const _TeamChannels({required this.channels, required this.members});

  final List<MattermostChannelDto> channels;
  final List<MattermostChannelMemberDto> members;
}
