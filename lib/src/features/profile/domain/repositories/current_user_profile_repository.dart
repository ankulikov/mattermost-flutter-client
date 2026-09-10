import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/profile/domain/models/current_user_profile.dart';

abstract interface class CurrentUserProfileRepository {
  Future<CurrentUserProfile> load();

  Future<Availability> setAvailability({
    required UserPresence presence,
    required DateTime? expiresAt,
  });

  Future<void> setCustomStatus({
    required String emoji,
    required String text,
    required CustomStatusDuration duration,
    required DateTime expiresAt,
  });

  Future<void> clearCustomStatus();
}
