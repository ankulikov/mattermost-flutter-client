import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/profile/domain/models/current_user_profile.dart';

abstract final class ProfileStrings {
  static const String title = 'Profile';
  static const String loading = 'Loading your profile';
  static const String loadFailed = 'Could not load your profile.';
  static const String updateFailed = 'Could not update your status.';
  static const String retry = 'Retry';
  static const String availability = 'Availability';
  static const String customStatus = 'Custom status';
  static const String clearCustomStatus = 'Clear custom status';
  static const String clearAfter = 'Clear after';
  static const String thirtyMinutes = '30 minutes';
  static const String oneHour = '1 hour';
  static const String tomorrowMorning = 'Tomorrow at 9:00 AM';
  static const String unlimited = 'No limit';
  static const String profileSettings = 'Profile';
  static const String security = 'Security';
  static const String notifications = 'Notifications';
  static const String display = 'Display';
  static const String appUpdates = 'App updates';
  static const String theme = 'Theme';
  static const String themeDescription =
      'Choose how Mattermost looks on this device.';
  static const String lightTheme = 'Light';
  static const String darkTheme = 'Dark';
  static const String updatingTheme = 'Updating theme';
  static const String themeUpdateFailed = 'Could not save your theme.';
  static const String logout = 'Log out';
  static const String doNotDisturbShort = 'DnD';
  static const String inAMeeting = 'In a meeting';
  static const String outForLunch = 'Out for lunch';
  static const String commuting = 'Commuting';
  static const String dayOff = 'Day off';
  static const String oneDay = '1 day';

  static String untilTime(String time) => 'Until $time';

  static String untilDateTime(String date, String time) =>
      'Until $date at $time';

  static String presence(UserPresence presence) => switch (presence) {
    UserPresence.online => 'Online',
    UserPresence.away => 'Away',
    UserPresence.doNotDisturb => 'Do not disturb',
    UserPresence.offline => 'Offline',
  };

  static String expiry(AvailabilityExpiry expiry) => switch (expiry) {
    AvailabilityExpiry.thirtyMinutes => thirtyMinutes,
    AvailabilityExpiry.oneHour => oneHour,
    AvailabilityExpiry.tomorrowMorning => tomorrowMorning,
    AvailabilityExpiry.unlimited => unlimited,
  };

  static String customDuration(CustomStatusDuration duration) =>
      switch (duration) {
        CustomStatusDuration.oneHour => oneHour,
        CustomStatusDuration.oneDay => oneDay,
      };
}
