import 'package:mattermost_flutter/src/features/users/domain/user_mention.dart';

abstract interface class UserMentionRepository {
  Future<List<UserMention>> resolveUsernames(List<String> usernames);
}
