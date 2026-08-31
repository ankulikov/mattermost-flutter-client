import 'package:mattermost_flutter/src/domain/models/user.dart';

abstract final class UserProfileStrings {
  static const String title = 'User profile';
  static const String loading = 'Loading user profile';
  static const String loadFailed = 'Could not load this user profile.';
  static const String retry = 'Retry';
  static const String close = 'Close';
  static const String email = 'Email';
  static const String position = 'Position';
  static const String unavailable = 'Not available';
  static const String message = 'Message';
  static const String messageFailed = 'Could not open a direct conversation.';

  static String presence(UserPresence value) => switch (value) {
    UserPresence.online => 'Online',
    UserPresence.away => 'Away',
    UserPresence.doNotDisturb => 'Do not disturb',
    UserPresence.offline => 'Offline',
  };
}
