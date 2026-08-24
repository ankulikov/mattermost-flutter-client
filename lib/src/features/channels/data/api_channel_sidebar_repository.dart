import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/features/auth/data/credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/channels/data/channel_sidebar_mapper.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar_repository.dart';

final class ApiChannelSidebarRepository implements ChannelSidebarRepository {
  ApiChannelSidebarRepository({
    required CredentialStore credentialStore,
    MattermostApiFactory clientFactory = const MattermostClientFactory(),
  }) : _credentialStore = credentialStore,
       _clientFactory = clientFactory;

  final CredentialStore _credentialStore;
  final MattermostApiFactory _clientFactory;

  @override
  Future<ChannelSidebarSnapshot> load(AuthSession session) async {
    final ({Uri serverUrl, String token})? credentials = await _credentialStore
        .read();
    if (credentials == null || credentials.serverUrl != session.serverUrl) {
      throw StateError('No credentials for active Mattermost account');
    }
    final MattermostApi api = _clientFactory.create(
      serverUrl: credentials.serverUrl,
      token: credentials.token,
    );
    final List<MattermostTeamDto> teams = await api.getTeamsForCurrentUser();
    if (teams.isEmpty) return const ChannelSidebarSnapshot();
    final SidebarTeam team = mapTeam(teams.first);
    final Future<List<MattermostChannelDto>> channelsFuture = api
        .getChannelsForUser(userId: session.userId, teamId: team.id);
    final Future<MattermostChannelCategoriesDto> categoriesFuture = api
        .getChannelCategories(userId: session.userId, teamId: team.id);
    final List<MattermostChannelDto> rawChannels = await channelsFuture;
    final MattermostChannelCategoriesDto categoryResponse =
        await categoriesFuture;
    List<SidebarChannel> channels = rawChannels
        .map(mapChannel)
        .toList(growable: false);
    try {
      channels = await _resolveDialogNames(
        api: api,
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

  Future<List<SidebarChannel>> _resolveDialogNames({
    required MattermostApi api,
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
        .expand((SidebarChannel item) => item.name.split('__'))
        .where((String id) => id.isNotEmpty && id != currentUserId)
        .toSet();
    final Future<List<MattermostUserDto>> directUsersFuture = api.getUsersByIds(
      directUserIds.toList(growable: false),
    );
    final Future<MattermostGroupChannelUsersDto> groupUsersFuture = api
        .getUsersForGroupChannels(
          groupChannels
              .map((SidebarChannel item) => item.id)
              .toList(growable: false),
        );
    final List<MattermostUserDto> directUsers = await directUsersFuture;
    final MattermostGroupChannelUsersDto groupUsers = await groupUsersFuture;
    final Map<String, String> directNames = <String, String>{
      for (final MattermostUserDto user in directUsers)
        if (user.id.isNotEmpty) user.id: userDisplayName(user),
    };

    return channels
        .map((SidebarChannel channel) {
          if (channel.kind == ChannelKind.directMessage) {
            final String? otherId = channel.name
                .split('__')
                .where((String id) => id != currentUserId)
                .firstOrNull;
            final String? name = directNames[otherId];
            return name == null ? channel : channel.withDisplayName(name);
          }
          if (channel.kind == ChannelKind.groupMessage) {
            final List<MattermostUserDto> users =
                groupUsers.usersByChannelId[channel.id] ??
                const <MattermostUserDto>[];
            final String name = users
                .where((MattermostUserDto user) => user.id != currentUserId)
                .map(userDisplayName)
                .join(', ');
            return name.isEmpty ? channel : channel.withDisplayName(name);
          }
          return channel;
        })
        .toList(growable: false);
  }
}
