import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/profile/domain/models/current_user_profile.dart';
import 'package:mattermost_flutter/src/features/profile/domain/policies/profile_status_expiration.dart';

void main() {
  final DateTime now = DateTime(2026, 9, 10, 22, 15);

  test('computes availability expirations including tomorrow morning', () {
    expect(
      availabilityExpiration(AvailabilityExpiry.thirtyMinutes, now),
      DateTime(2026, 9, 10, 22, 45),
    );
    expect(
      availabilityExpiration(AvailabilityExpiry.oneHour, now),
      DateTime(2026, 9, 10, 23, 15),
    );
    expect(
      availabilityExpiration(AvailabilityExpiry.tomorrowMorning, now),
      DateTime(2026, 9, 11, 9),
    );
    expect(availabilityExpiration(AvailabilityExpiry.unlimited, now), isNull);
  });

  test('computes quick custom status expirations', () {
    expect(
      customStatusExpiration(CustomStatusDuration.oneHour, now),
      DateTime(2026, 9, 10, 23, 15),
    );
    expect(
      customStatusExpiration(CustomStatusDuration.oneDay, now),
      DateTime(2026, 9, 11, 22, 15),
    );
  });

  test('matches a quick status only by both emoji and text', () {
    const CustomStatus current = CustomStatus(
      emoji: 'calendar',
      text: 'In a meeting',
    );

    expect(
      current.matches(
        const QuickCustomStatus(
          emoji: 'calendar',
          text: 'In a meeting',
          duration: CustomStatusDuration.oneHour,
        ),
      ),
      isTrue,
    );
    expect(
      current.matches(
        const QuickCustomStatus(
          emoji: 'calendar',
          text: 'Different text',
          duration: CustomStatusDuration.oneHour,
        ),
      ),
      isFalse,
    );
    expect(
      current.matches(
        const QuickCustomStatus(
          emoji: 'bus',
          text: 'In a meeting',
          duration: CustomStatusDuration.oneHour,
        ),
      ),
      isFalse,
    );
  });
}
