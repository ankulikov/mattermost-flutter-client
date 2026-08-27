import 'package:mattermost_flutter/src/features/users/domain/user_profile.dart';

abstract interface class UserProfileRepository {
  Future<UserProfile> getById(String userId);
}
