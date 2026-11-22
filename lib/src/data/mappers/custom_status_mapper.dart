import 'dart:convert';

import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';

({String emoji, String text, DateTime? expiresAt})? parseCustomStatus(
  UserPropsDto? props,
  DateTime now,
) {
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
  return (emoji: emoji, text: text, expiresAt: expiresAt);
}
