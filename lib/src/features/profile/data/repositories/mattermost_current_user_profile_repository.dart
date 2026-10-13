import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/profile/data/mappers/current_user_profile_mapper.dart';
import 'package:mattermost_flutter/src/features/profile/domain/models/current_user_profile.dart';
import 'package:mattermost_flutter/src/features/profile/domain/repositories/current_user_profile_repository.dart';

final class MattermostCurrentUserProfileRepository
    implements CurrentUserProfileRepository {
  MattermostCurrentUserProfileRepository({
    required MattermostProfileApi api,
    required String userId,
    DateTime Function()? now,
  }) : _api = api,
       _userId = userId,
       _now = now ?? DateTime.now;

  final MattermostProfileApi _api;
  final String _userId;
  final DateTime Function() _now;

  @override
  Future<CurrentUserProfile> load() async {
    final List<Object> response = await Future.wait<Object>(<Future<Object>>[
      _api.getCurrentUser(),
      _api.getUserStatus(_userId),
    ]);
    final MattermostUserDto user = response[0] as MattermostUserDto;
    final MattermostUserStatusDto status =
        response[1] as MattermostUserStatusDto;
    if (user.id != _userId || status.userId != _userId) {
      throw const FormatException('Mattermost returned another user profile');
    }
    return mapCurrentUserProfile(user: user, status: status, now: _now());
  }

  @override
  Future<Availability> setAvailability({
    required UserPresence presence,
    required DateTime? expiresAt,
  }) async {
    final MattermostUserStatusDto status = await _api.updateUserStatus(
      userId: _userId,
      status: _presenceName(presence),
      dndEndTime: expiresAt == null
          ? 0
          : expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000,
    );
    final Availability serverValue = mapAvailability(status);
    // Current Mattermost servers only persist dnd_end_time for DND. Keep the
    // requested expiry visible for away/offline for this open profile surface.
    return Availability(
      presence: serverValue.presence,
      expiresAt: serverValue.expiresAt ?? expiresAt,
    );
  }

  @override
  Future<void> setCustomStatus({
    required String emoji,
    required String text,
    required CustomStatusDuration duration,
    required DateTime expiresAt,
  }) => _api.updateUserCustomStatus(
    userId: _userId,
    status: MattermostCustomStatusRequestDto(
      emoji: emoji,
      text: text,
      duration: switch (duration) {
        CustomStatusDuration.oneHour => 'one_hour',
        CustomStatusDuration.oneDay => 'date_and_time',
      },
      expiresAt: expiresAt,
    ),
  );

  @override
  Future<void> clearCustomStatus() => _api.removeUserCustomStatus(_userId);

  static String _presenceName(UserPresence presence) => switch (presence) {
    UserPresence.online => 'online',
    UserPresence.away => 'away',
    UserPresence.doNotDisturb => 'dnd',
    UserPresence.offline => 'offline',
  };
}
