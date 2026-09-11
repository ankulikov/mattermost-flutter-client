import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';

/// Applies participant-derived names to direct and group-message channels.
///
/// Mattermost stores dialog participant IDs in a channel's technical name.
/// Callers obtain participant profiles through their API boundary and pass them
/// here so every UI entry point uses the same display projection.
List<SidebarChannel> resolveDialogDisplayNames({
  required Iterable<SidebarChannel> channels,
  required String currentUserId,
  required Map<String, UserSummary> directUsersById,
  required Map<String, List<UserSummary>> groupUsersByChannelId,
}) => channels
    .map((SidebarChannel channel) {
      if (channel.kind == ChannelKind.directMessage) {
        final String? participantId = directParticipantId(
          channelName: channel.name,
          currentUserId: currentUserId,
        );
        final UserSummary? participant = directUsersById[participantId];
        return participant == null
            ? channel
            : channel.withDirectUser(
                displayName: participant.fullName,
                userId: participant.id,
                profileImageUpdatedAt: participant.profileImageUpdatedAt,
              );
      }
      if (channel.kind == ChannelKind.groupMessage) {
        final String name =
            (groupUsersByChannelId[channel.id] ?? const <UserSummary>[])
                .where((UserSummary user) => user.id != currentUserId)
                .map((UserSummary user) => user.fullName)
                .join(', ');
        return name.isEmpty ? channel : channel.withDisplayName(name);
      }
      return channel;
    })
    .toList(growable: false);

String? directParticipantId({
  required String channelName,
  required String currentUserId,
}) {
  final List<String> participantIds = channelName
      .split('__')
      .where((String id) => id.isNotEmpty)
      .toList(growable: false);
  for (final String id in participantIds) {
    if (id != currentUserId) return id;
  }
  return participantIds.contains(currentUserId) ? currentUserId : null;
}
