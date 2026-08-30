import 'package:mattermost_flutter/src/domain/models/user_mention.dart';

abstract interface class UserMentionRepository {
  Future<List<UserMention>> resolveUsernames(List<String> usernames);
}
