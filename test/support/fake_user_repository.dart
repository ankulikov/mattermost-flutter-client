import 'dart:typed_data';

import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/models/user_avatar.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_repository.dart';

final class FakeUserRepository implements UserRepository {
  FakeUserRepository({Map<String, UserSummary>? users})
    : _users = <String, UserSummary>{...?users};

  final Map<String, UserSummary> _users;
  final List<List<String>> requestedIdBatches = <List<String>>[];

  @override
  Future<List<UserSummary>> getUsers(
    List<String> userIds, {
    UserFreshness freshness = UserFreshness.cached,
  }) async {
    requestedIdBatches.add(List<String>.of(userIds));
    return userIds.map(_summary).toList(growable: false);
  }

  @override
  Future<UserSummary?> getUserByUsername(
    String username, {
    UserFreshness freshness = UserFreshness.cached,
  }) async => _users.values.cast<UserSummary?>().firstWhere(
    (UserSummary? user) =>
        user?.username.toLowerCase() == username.toLowerCase(),
    orElse: () => null,
  );

  @override
  Future<UserProfile> getProfile(
    String userId, {
    UserFreshness freshness = UserFreshness.fresh,
  }) async {
    final UserSummary user = _summary(userId);
    return UserProfile(
      id: user.id,
      firstName: user.firstName,
      lastName: user.lastName,
      username: user.username,
      nickname: user.nickname,
      position: user.position,
      email: user.email,
      profileImageUpdatedAt: user.profileImageUpdatedAt,
      presence: UserPresence.offline,
    );
  }

  @override
  Future<UserAvatar> loadAvatar({
    required String userId,
    required int profileImageUpdatedAt,
  }) async => UserAvatar(bytes: Uint8List(0));

  @override
  Future<List<UserSummary>> resolveUsersByUsernames(
    List<String> usernames, {
    UserFreshness freshness = UserFreshness.cached,
  }) async => _users.values
      .where(
        (UserSummary user) => usernames
            .map((String username) => username.toLowerCase())
            .contains(user.username.toLowerCase()),
      )
      .toList(growable: false);

  UserSummary _summary(String id) => _users.putIfAbsent(id, () {
    final (String firstName, String lastName) name = switch (id) {
      'ada' => ('Ada', 'Lovelace'),
      'grace' || 'missing-author' => ('Grace', 'Hopper'),
      _ => (id, ''),
    };
    return UserSummary(
      id: id,
      username: id,
      firstName: name.$1,
      lastName: name.$2,
      nickname: '',
      position: '',
      email: '',
      profileImageUpdatedAt: 99,
    );
  });
}
