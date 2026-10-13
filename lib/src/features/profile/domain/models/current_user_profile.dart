import 'package:mattermost_flutter/src/domain/models/user.dart';

enum AvailabilityExpiry { thirtyMinutes, oneHour, tomorrowMorning, unlimited }

enum CustomStatusDuration { oneHour, oneDay }

final class Availability {
  const Availability({required this.presence, this.expiresAt});

  final UserPresence presence;
  final DateTime? expiresAt;
}

final class CustomStatus {
  const CustomStatus({required this.emoji, required this.text, this.expiresAt});

  final String emoji;
  final String text;
  final DateTime? expiresAt;

  bool matches(QuickCustomStatus action) =>
      emoji == action.emoji && text == action.text;
}

final class CurrentUserProfile {
  const CurrentUserProfile({
    required this.user,
    required this.availability,
    this.customStatus,
  });

  final UserSummary user;
  final Availability availability;
  final CustomStatus? customStatus;

  CurrentUserProfile copyWith({
    Availability? availability,
    CustomStatus? customStatus,
    bool clearCustomStatus = false,
  }) => CurrentUserProfile(
    user: user,
    availability: availability ?? this.availability,
    customStatus: clearCustomStatus ? null : customStatus ?? this.customStatus,
  );
}

final class QuickCustomStatus {
  const QuickCustomStatus({
    required this.emoji,
    required this.text,
    required this.duration,
  });

  final String emoji;
  final String text;
  final CustomStatusDuration duration;
}
