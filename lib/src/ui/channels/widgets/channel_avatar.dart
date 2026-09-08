import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/ui/users/widgets/user_avatar_image.dart';

class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({required this.channel, this.size = 24, super.key});

  final SidebarChannel channel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final SidebarProfileImage? profileImage = channel.profileImage;
    if (channel.kind == ChannelKind.directMessage && profileImage != null) {
      return UserAvatarImage(
        userId: profileImage.userId,
        displayName: channel.displayName,
        profileImageUpdatedAt: profileImage.updatedAt,
        radius: size / 2,
      );
    }
    return SizedBox.square(
      dimension: size,
      child: Icon(_iconFor(channel.kind), size: size * 0.75),
    );
  }

  IconData _iconFor(ChannelKind kind) => switch (kind) {
    ChannelKind.publicChannel => Icons.tag,
    ChannelKind.privateChannel => Icons.lock_outline,
    ChannelKind.directMessage => Icons.person_outline,
    ChannelKind.groupMessage => Icons.group_outlined,
  };
}
