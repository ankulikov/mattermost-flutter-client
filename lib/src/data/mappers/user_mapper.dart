import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/database/user_profile_cache_dao.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/models/user_mention.dart';
import 'package:mattermost_flutter/src/domain/policies/user_display_name.dart';

UserSummary mapUserSummary(MattermostUserDto user) => UserSummary(
  id: user.id,
  firstName: user.firstName,
  lastName: user.lastName,
  username: user.username,
  nickname: user.nickname,
  position: user.position,
  email: user.email,
  profileImageUpdatedAt: user.profileImageUpdatedAt,
);

UserSummary mapCachedUserSummary(CachedUserProfile profile) => UserSummary(
  id: profile.userId,
  firstName: profile.firstName,
  lastName: profile.lastName,
  username: profile.username,
  nickname: profile.nickname,
  position: profile.position,
  email: profile.email,
  profileImageUpdatedAt: profile.profileImageUpdatedAt,
);

UserProfile mapUserProfile({
  required MattermostUserDto user,
  required MattermostUserStatusDto status,
}) => UserProfile(
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

CachedUserProfile cacheUserSummary(UserSummary user, DateTime expiresAt) =>
    CachedUserProfile(
      userId: user.id,
      firstName: user.firstName,
      lastName: user.lastName,
      username: user.username,
      nickname: user.nickname,
      position: user.position,
      email: user.email,
      profileImageUpdatedAt: user.profileImageUpdatedAt,
      expiresAt: expiresAt,
    );

UserMention mapUserMention(UserSummary user) => UserMention(
  userId: user.id,
  username: user.username,
  displayName: resolveUserDisplayName(
    id: user.id,
    username: user.username,
    nickname: user.nickname,
    firstName: user.firstName,
    lastName: user.lastName,
  ),
);
