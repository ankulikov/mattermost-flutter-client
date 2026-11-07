import 'dart:convert';

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
  isBot: user.isBot,
  customStatus: mapUserCustomStatus(user.props, DateTime.now()),
);

UserCustomStatus? mapUserCustomStatus(UserPropsDto? props, DateTime now) {
  final JsonValueDto? raw = props?.values['customStatus'];
  Object? decoded;
  try {
    decoded = switch (raw) {
      JsonStringDto(:final String value) when value.isNotEmpty => jsonDecode(
        value,
      ),
      JsonObjectDto(:final Map<String, JsonValueDto> values) => values.map(
        (String key, JsonValueDto value) =>
            MapEntry<String, Object?>(key, switch (value) {
              JsonStringDto(:final String value) => value,
              _ => null,
            }),
      ),
      _ => null,
    };
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  final String emoji = decoded['emoji'] is String
      ? decoded['emoji']! as String
      : '';
  final String text = decoded['text'] is String
      ? decoded['text']! as String
      : '';
  if (emoji.isEmpty && text.isEmpty) return null;
  final DateTime? parsedExpiresAt = decoded['expires_at'] is String
      ? DateTime.tryParse(decoded['expires_at']! as String)
      : null;
  final DateTime? expiresAt = parsedExpiresAt?.year == 1
      ? null
      : parsedExpiresAt;
  if (expiresAt != null && !expiresAt.isAfter(now)) return null;
  return UserCustomStatus(emoji: emoji, text: text, expiresAt: expiresAt);
}

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
  presence: mapUserPresence(status.status) ?? UserPresence.offline,
  profileImageUpdatedAt: user.profileImageUpdatedAt,
  isBot: user.isBot,
);

UserPresence? mapUserPresence(String status) => switch (status) {
  'online' => UserPresence.online,
  'away' => UserPresence.away,
  'dnd' => UserPresence.doNotDisturb,
  'offline' => UserPresence.offline,
  _ => null,
};

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
