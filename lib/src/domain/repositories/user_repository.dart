import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/models/user_avatar.dart';

/// Chooses whether summary lookup may use the account-scoped profile cache.
enum UserFreshness { cached, fresh }

/// The single public contract for the user aggregate.
abstract interface class UserRepository {
  Future<List<UserSummary>> getUsers(
    List<String> userIds, {
    UserFreshness freshness = UserFreshness.cached,
  });

  Future<UserSummary?> getUserByUsername(
    String username, {
    UserFreshness freshness = UserFreshness.cached,
  });

  Future<List<UserSummary>> resolveUsersByUsernames(
    List<String> usernames, {
    UserFreshness freshness = UserFreshness.cached,
  });

  /// Loads a complete, current profile and current presence without batch cache.
  Future<UserProfile> getProfile(
    String userId, {
    UserFreshness freshness = UserFreshness.fresh,
  });

  Future<UserAvatar> loadAvatar({
    required String userId,
    required int profileImageUpdatedAt,
  });
}
