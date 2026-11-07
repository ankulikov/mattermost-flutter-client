import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/ui/channels/channel_sidebar_strings.dart';
import 'package:mattermost_flutter/src/ui/users/user_profile_strings.dart';
import 'package:mattermost_flutter/src/ui/users/widgets/user_avatar_image.dart';

class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({required this.channel, this.size = 24, super.key});

  final SidebarChannel channel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final SidebarProfileImage? profileImage = channel.profileImage;
    final Widget avatar =
        channel.kind == ChannelKind.directMessage && profileImage != null
        ? UserAvatarImage(
            userId: profileImage.userId,
            displayName: channel.displayName,
            profileImageUpdatedAt: profileImage.updatedAt,
            radius: size / 2,
          )
        : SizedBox.square(
            dimension: size,
            child: Icon(_iconFor(channel.kind), size: size * 0.75),
          );
    if (channel.kind != ChannelKind.directMessage || channel.isBot) {
      return avatar;
    }

    final UserPresence? presence = channel.presence;
    final String label = presence == null
        ? ChannelSidebarStrings.statusUnavailable
        : UserProfileStrings.presence(presence);
    final Color color = switch (presence) {
      UserPresence.online => const Color(0xff3db887),
      UserPresence.away => const Color(0xffffbc1f),
      UserPresence.doNotDisturb => const Color(0xffd24b4e),
      UserPresence.offline || null => Theme.of(context).colorScheme.outline,
    };
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            avatar,
            PositionedDirectional(
              end: -2,
              bottom: -2,
              child: Container(
                key: ValueKey<String>('channel-presence-${channel.id}'),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(ChannelKind kind) => switch (kind) {
    ChannelKind.publicChannel => Icons.tag,
    ChannelKind.privateChannel => Icons.lock_outline,
    ChannelKind.directMessage => Icons.person_outline,
    ChannelKind.groupMessage => Icons.group_outlined,
  };
}
