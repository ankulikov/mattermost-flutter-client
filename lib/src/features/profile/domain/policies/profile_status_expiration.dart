import 'package:mattermost_flutter/src/features/profile/domain/models/current_user_profile.dart';

DateTime? availabilityExpiration(AvailabilityExpiry expiry, DateTime now) =>
    switch (expiry) {
      AvailabilityExpiry.thirtyMinutes => now.add(const Duration(minutes: 30)),
      AvailabilityExpiry.oneHour => now.add(const Duration(hours: 1)),
      AvailabilityExpiry.tomorrowMorning => DateTime(
        now.year,
        now.month,
        now.day + 1,
        9,
      ),
      AvailabilityExpiry.unlimited => null,
    };

DateTime customStatusExpiration(CustomStatusDuration duration, DateTime now) =>
    switch (duration) {
      CustomStatusDuration.oneHour => now.add(const Duration(hours: 1)),
      CustomStatusDuration.oneDay => now.add(const Duration(days: 1)),
    };
