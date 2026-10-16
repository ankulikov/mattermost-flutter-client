import 'dart:convert';

import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/channel_sidebar_mapper.dart';
import 'package:mattermost_flutter/src/data/mappers/dialog_display_name_mapper.dart';
import 'package:mattermost_flutter/src/data/mappers/user_mapper.dart';
import 'package:mattermost_flutter/src/data/realtime/session_realtime_service.dart';
import 'package:mattermost_flutter/src/data/realtime/websocket_gateway.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/channel_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_repository.dart';

final class MattermostChannelRepository
    implements ChannelRepository, ChannelSidebarRealtimeRepository {
  const MattermostChannelRepository({
    required MattermostApi api,
    required UserRepository users,
    SessionRealtimeService? realtime,
  }) : _api = api,
       _users = users,
       _realtime = realtime;

  static const Set<String> _sidebarEventNames = <String>{
    'posted',
    'channel_viewed',
    'post_unread',
    'channel_member_updated',
  };

  final MattermostApi _api;
  final UserRepository _users;
  final SessionRealtimeService? _realtime;

  @override
  Future<ChannelSidebarSnapshot> load(AuthSession session) async {
    final List<MattermostTeamDto> teams = await _api.getTeamsForCurrentUser();
    if (teams.isEmpty) return const ChannelSidebarSnapshot();
    final SidebarTeam team = mapTeam(teams.first);
    final Future<List<MattermostChannelDto>> channelsFuture = _api
        .getChannelsForUser(userId: session.userId, teamId: team.id);
    final Future<MattermostChannelCategoriesDto> categoriesFuture = _api
        .getChannelCategories(userId: session.userId, teamId: team.id);
    final Future<List<MattermostChannelMemberDto>> membershipsFuture = _api
        .getChannelMembersForUser(userId: session.userId, teamId: team.id);
    final (
      List<MattermostChannelDto> rawChannels,
      MattermostChannelCategoriesDto categoryResponse,
      List<MattermostChannelMemberDto> memberships,
    ) = await (
      channelsFuture,
      categoriesFuture,
      membershipsFuture,
    ).wait;
    final Map<String, MattermostChannelMemberDto> membershipsByChannel =
        <String, MattermostChannelMemberDto>{
          for (final MattermostChannelMemberDto member in memberships)
            member.channelId: member,
        };
    List<SidebarChannel> channels = rawChannels
        .map((MattermostChannelDto rawChannel) {
          final SidebarChannel channel = mapChannel(
            rawChannel,
            teamName: team.name,
          );
          return mapChannelMembership(
            channel: channel,
            rawChannel: rawChannel,
            member: membershipsByChannel[channel.id],
          );
        })
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

  @override
  Stream<ChannelSidebarRealtimeEvent> watchSidebar({
    required AuthSession session,
  }) {
    final SessionRealtimeService? realtime = _realtime;
    if (realtime == null) {
      return const Stream<ChannelSidebarRealtimeEvent>.empty();
    }
    return realtime
        .watch(
          session: session,
          subscription: const SessionRealtimeSubscription(
            eventNames: _sidebarEventNames,
          ),
        )
        .map((SessionRealtimeSignal signal) {
          switch (signal) {
            case SessionRealtimeRecoveryRequired():
              return const ChannelSidebarRefreshRequired();
            case SessionRealtimeConnectionChanged():
              return null;
            case SessionRealtimeEventReceived(:final event):
              return _mapSidebarEvent(session, event);
          }
        })
        .where((ChannelSidebarRealtimeEvent? event) => event != null)
        .cast<ChannelSidebarRealtimeEvent>();
  }

  @override
  Future<void> markChannelViewed({
    required AuthSession session,
    required String channelId,
    String? previousChannelId,
  }) => _api.viewChannel(
    userId: session.userId,
    channelId: channelId,
    previousChannelId: previousChannelId,
  );

  ChannelSidebarRealtimeEvent? _mapSidebarEvent(
    AuthSession session,
    MattermostWebSocketEvent event,
  ) {
    switch (event.name) {
      case 'posted':
        final MattermostPostDto? post = _postFromEvent(event.data);
        if (post == null || post.channelId.isEmpty) {
          return const ChannelSidebarRefreshRequired();
        }
        if (post.userId == session.userId) return null;
        return ChannelSidebarMessagePosted(
          channelId: post.channelId,
          isThreadReply: post.rootId.isNotEmpty,
        );
      case 'channel_viewed':
        final String channelId = _eventChannelId(event);
        return channelId.isEmpty
            ? const ChannelSidebarRefreshRequired()
            : ChannelSidebarUnreadChanged(
                channelId: channelId,
                isUnread: false,
              );
      case 'post_unread':
        final String channelId = _eventChannelId(event);
        return channelId.isEmpty
            ? const ChannelSidebarRefreshRequired()
            : ChannelSidebarUnreadChanged(channelId: channelId, isUnread: true);
      case 'channel_member_updated':
        return const ChannelSidebarRefreshRequired();
      default:
        return null;
    }
  }

  static String _eventChannelId(MattermostWebSocketEvent event) {
    if (event.channelId.isNotEmpty) return event.channelId;
    final Object? channelId = event.data['channel_id'];
    return channelId is String ? channelId : '';
  }

  static MattermostPostDto? _postFromEvent(Map<String, Object?> data) {
    final Object? raw = data['post'];
    final Object? decoded;
    try {
      decoded = raw is String ? jsonDecode(raw) : raw;
    } on FormatException {
      return null;
    }
    if (decoded is! Map<Object?, Object?>) return null;
    return MattermostPostDto.fromJson(
      decoded.map(
        (Object? key, Object? value) => MapEntry<String, Object?>(
          key is String ? key : key.toString(),
          value,
        ),
      ),
    );
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
