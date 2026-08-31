import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/policies/user_display_name.dart';

final class UserMention {
  const UserMention({
    required this.userId,
    required this.username,
    required this.displayName,
  });

  final String userId;
  final String username;
  final String displayName;
}

final RegExp _userMentionPattern = RegExp(
  r'\B@([a-z0-9][a-z0-9._-]*)',
  caseSensitive: false,
);

List<String> extractUserMentionNames(String message) => _userMentionPattern
    .allMatches(message)
    .map((RegExpMatch match) => match.group(1)!.toLowerCase())
    .toSet()
    .toList(growable: false);

String userMentionLookupKey(String message) {
  final List<String> usernames = extractUserMentionNames(message)..sort();
  return usernames.join(',');
}

UserMention userMentionFromSummary(UserSummary user) => UserMention(
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
