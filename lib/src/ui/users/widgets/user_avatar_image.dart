import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/domain/models/user_avatar.dart';
import 'package:mattermost_flutter/src/ui/core/widgets/avatar_initials.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

/// A non-interactive user avatar that paints a fallback immediately.
///
/// Only visible widgets subscribe to the auto-disposed provider. The shared
/// user repository supplies versioned cached bytes asynchronously.
class UserAvatarImage extends ConsumerWidget {
  const UserAvatarImage({
    required this.userId,
    required this.displayName,
    required this.profileImageUpdatedAt,
    required this.radius,
    super.key,
  });

  final String userId;
  final String displayName;
  final int profileImageUpdatedAt;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<UserAvatar?> avatar = ref.watch(
      userAvatarProvider((
        userId: userId,
        profileImageUpdatedAt: profileImageUpdatedAt,
      )),
    );
    final Widget fallback = CircleAvatar(
      key: ValueKey<String>('user-avatar-fallback-$userId'),
      radius: radius,
      backgroundColor: _avatarColor(userId),
      foregroundColor: Colors.white,
      child: Text(
        avatarInitials(displayName),
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: Colors.white),
      ),
    );
    final double diameter = radius * 2;
    final int cacheWidth = (diameter * MediaQuery.devicePixelRatioOf(context))
        .ceil();
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: diameter,
        child: ClipOval(
          child: avatar.when(
            data: (UserAvatar? value) => value == null
                ? fallback
                : Image.memory(
                    value.bytes,
                    key: ValueKey<String>('user-avatar-image-$userId'),
                    fit: BoxFit.cover,
                    cacheWidth: cacheWidth,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                    errorBuilder:
                        (BuildContext context, Object _, StackTrace? _) {
                          return fallback;
                        },
                  ),
            loading: () => fallback,
            error: (Object _, StackTrace _) => fallback,
          ),
        ),
      ),
    );
  }
}

Color _avatarColor(String id) {
  const List<Color> colors = <Color>[
    Color(0xff3f51b5),
    Color(0xff00796b),
    Color(0xffad4b00),
    Color(0xff7b1fa2),
  ];
  final int sum = id.codeUnits.fold(0, (int value, int unit) => value + unit);
  return colors[sum % colors.length];
}
