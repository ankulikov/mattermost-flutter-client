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
    final Future<List<MattermostUserDto>> userFuture = _api.getUsersByIds(
      <String>[userId],
    );
    final Future<MattermostUserStatusDto> statusFuture = _api.getUserStatus(
      userId,
    );
    final List<Object> result = await Future.wait<Object>(<Future<Object>>[
      userFuture,
      statusFuture,
    ]);
    final List<MattermostUserDto> users = result[0] as List<MattermostUserDto>;
    final MattermostUserStatusDto status = result[1] as MattermostUserStatusDto;
    final MattermostUserDto? user = users
        .where((MattermostUserDto item) => item.id == userId)
        .firstOrNull;
    if (user == null) {
      throw StateError('Mattermost returned no profile for user $userId');
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
