import 'package:mattermost_flutter/src/domain/models/user_avatar.dart';

abstract interface class UserAvatarRepository {
  Future<UserAvatar> getAvatar({
    required String accountId,
    required String userId,
    required int profileImageUpdatedAt,
  });
}
