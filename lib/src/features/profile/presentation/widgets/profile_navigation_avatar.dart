import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/profile/domain/models/current_user_profile.dart';
import 'package:mattermost_flutter/src/ui/users/widgets/user_avatar_image.dart';

class ProfileNavigationAvatar extends StatelessWidget {
  const ProfileNavigationAvatar({required this.profile, super.key});

  final CurrentUserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final CurrentUserProfile? value = profile;
    if (value == null) return const Icon(Icons.account_circle_outlined);
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        UserAvatarImage(
          userId: value.user.id,
          displayName: value.user.fullName,
          profileImageUpdatedAt: value.user.profileImageUpdatedAt,
          radius: 12,
        ),
        PositionedDirectional(
          end: -3,
          bottom: -3,
          child: Container(
            key: const ValueKey<String>('profile-navigation-presence'),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: presenceColor(context, value.availability.presence),
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Color presenceColor(BuildContext context, UserPresence presence) =>
    switch (presence) {
      UserPresence.online => const Color(0xff3db887),
      UserPresence.away => const Color(0xffffbc1f),
      UserPresence.doNotDisturb => const Color(0xffd24b4e),
      UserPresence.offline => Theme.of(context).colorScheme.outline,
    };
