import 'package:mattermost_flutter/src/domain/models/user.dart';

abstract interface class UserProfileRepository {
  Future<UserProfile> getById(String userId);
}
