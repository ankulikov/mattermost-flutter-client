import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_profile.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_profile_repository.dart';

final class ApiUserProfileRepository implements UserProfileRepository {
  const ApiUserProfileRepository({required MattermostApi api}) : _api = api;

  final MattermostApi _api;

  @override
  Future<UserProfile> getById(String userId) async {
    if (userId.isEmpty) throw ArgumentError.value(userId, 'userId');
    final Future<MattermostUserDto> userFuture = _api.getUserById(userId);
    final Future<MattermostUserStatusDto> statusFuture = _api.getUserStatus(
      userId,
    );
    final List<Object> result = await Future.wait<Object>(<Future<Object>>[
      userFuture,
      statusFuture,
    ]);
    final MattermostUserDto user = result[0] as MattermostUserDto;
    final MattermostUserStatusDto status = result[1] as MattermostUserStatusDto;
    if (user.id != userId) {
      throw FormatException(
        'Mattermost returned profile ${user.id} when $userId was requested',
      );
    }
    return UserProfile(
      id: user.id,
      firstName: user.firstName,
      lastName: user.lastName,
      username: user.username,
      nickname: user.nickname,
      position: user.position,
      email: user.email,
      presence: switch (status.status) {
        'online' => UserPresence.online,
        'away' => UserPresence.away,
        'dnd' => UserPresence.doNotDisturb,
        _ => UserPresence.offline,
      },
      profileImageUpdatedAt: user.profileImageUpdatedAt,
    );
  }
}
