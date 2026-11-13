import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/mappers/user_mapper.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/profile/domain/models/current_user_profile.dart';

CurrentUserProfile mapCurrentUserProfile({
  required MattermostUserDto user,
  required MattermostUserStatusDto status,
  required DateTime now,
}) => CurrentUserProfile(
  user: mapUserSummary(user),
  availability: mapAvailability(status),
  customStatus: mapCurrentCustomStatus(user.props, now),
);

Availability mapAvailability(MattermostUserStatusDto status) => Availability(
  presence: switch (status.status) {
    'online' => UserPresence.online,
    'away' => UserPresence.away,
    'dnd' => UserPresence.doNotDisturb,
    _ => UserPresence.offline,
  },
  expiresAt: status.dndEndTime > 0
      ? DateTime.fromMillisecondsSinceEpoch(
          status.dndEndTime * 1000,
          isUtc: true,
        )
      : null,
);

CustomStatus? mapCurrentCustomStatus(UserPropsDto? props, DateTime now) {
  final UserCustomStatus? status = mapUserCustomStatus(props, now);
  return status == null
      ? null
      : CustomStatus(
          emoji: status.emoji,
          text: status.text,
          expiresAt: status.expiresAt,
        );
}
