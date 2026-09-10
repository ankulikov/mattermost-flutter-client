import 'dart:convert';

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
  return CustomStatus(emoji: emoji, text: text, expiresAt: expiresAt);
}
