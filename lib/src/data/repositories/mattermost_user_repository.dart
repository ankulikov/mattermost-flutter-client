import 'dart:typed_data';

import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/cache/avatar_cache.dart';
import 'package:mattermost_flutter/src/data/database/user_profile_cache_dao.dart';
import 'package:mattermost_flutter/src/data/mappers/user_mapper.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/models/user_avatar.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_repository.dart';

/// Applies account-scoped profile and avatar cache policy above raw user REST.
final class MattermostUserRepository implements UserRepository {
  MattermostUserRepository({
    required MattermostApi api,
    required UserProfileCache cache,
    required UserAvatarCache avatarCache,
    required String accountScopeId,
    DateTime Function()? now,
  }) : _api = api,
       _cache = cache,
       _avatarCache = avatarCache,
       _accountScopeId = accountScopeId,
       _now = now ?? DateTime.now;

  static const Duration cacheLifetime = Duration(days: 7);

  final MattermostApi _api;
  final UserProfileCache _cache;
  final UserAvatarCache _avatarCache;
  final String _accountScopeId;
  final DateTime Function() _now;
  final Map<String, Future<UserAvatar>> _avatarInFlight =
      <String, Future<UserAvatar>>{};

  @override
  Future<List<UserSummary>> getUsers(
    List<String> userIds, {
    UserFreshness freshness = UserFreshness.cached,
  }) async {
    final List<String> requestedIds = _uniqueNonEmpty(userIds);
    if (requestedIds.isEmpty) return const <UserSummary>[];
    if (freshness == UserFreshness.fresh) {
      return _loadIds(requestedIds, cacheResult: true);
    }

    final DateTime checkedAt = _now().toUtc();
    final List<CachedUserProfile> cached = await _cache.getByIds(
      accountId: _accountScopeId,
      userIds: requestedIds,
    );
    final Map<String, UserSummary> usersById = <String, UserSummary>{
      for (final CachedUserProfile profile in cached)
        if (_isFresh(profile.expiresAt, checkedAt))
          profile.userId: mapCachedUserSummary(profile),
    };
    final List<String> staleOrMissing = requestedIds
        .where((String id) => !usersById.containsKey(id))
        .toList(growable: false);
    if (staleOrMissing.isNotEmpty) {
      final List<UserSummary> loaded = await _loadIds(
        staleOrMissing,
        cacheResult: true,
      );
      usersById.addEntries(
        loaded.map(
          (UserSummary user) => MapEntry<String, UserSummary>(user.id, user),
        ),
      );
    }
    return requestedIds
        .map((String id) => usersById[id])
        .whereType<UserSummary>()
        .toList(growable: false);
  }

  @override
  Future<UserSummary?> getUserByUsername(
    String username, {
    UserFreshness freshness = UserFreshness.cached,
  }) async {
    final List<UserSummary> users = await resolveUsersByUsernames(<String>[
      username,
    ], freshness: freshness);
    return users.isEmpty ? null : users.single;
  }

  @override
  Future<List<UserSummary>> resolveUsersByUsernames(
    List<String> usernames, {
    UserFreshness freshness = UserFreshness.cached,
  }) async {
    final List<String> requested = _uniqueNormalizedUsernames(usernames);
    if (requested.isEmpty) return const <UserSummary>[];
    if (freshness == UserFreshness.fresh) {
      final List<MattermostUserDto> loaded = await _api.getUsersByUsernames(
        requested,
      );
      final Set<String> expected = requested.toSet();
      final List<UserSummary> valid = loaded
          .where(
            (MattermostUserDto user) =>
                user.id.isNotEmpty &&
                expected.contains(user.username.toLowerCase()),
          )
          .map(mapUserSummary)
          .toList(growable: false);
      await _cacheUsers(valid);
      return _orderByUsername(requested, valid);
    }

    final DateTime checkedAt = _now().toUtc();
    final List<CachedUserProfile> cached = await _cache.getByUsernames(
      accountId: _accountScopeId,
      usernames: requested,
    );
    final Map<String, UserSummary> usersByUsername = <String, UserSummary>{
      for (final CachedUserProfile profile in cached)
        if (_isFresh(profile.expiresAt, checkedAt))
          profile.username.toLowerCase(): mapCachedUserSummary(profile),
    };
    final List<CachedUserProfile> stale = cached
        .where(
          (CachedUserProfile profile) =>
              !_isFresh(profile.expiresAt, checkedAt),
        )
        .toList(growable: false);
    final Set<String> staleIds = stale
        .map((CachedUserProfile profile) => profile.userId)
        .where((String id) => id.isNotEmpty)
        .toSet();
    if (staleIds.isNotEmpty) {
      final List<UserSummary> refreshed = await _loadIds(
        staleIds.toList(growable: false),
        cacheResult: true,
      );
      usersByUsername.addEntries(
        refreshed.map(
          (UserSummary user) =>
              MapEntry<String, UserSummary>(user.username.toLowerCase(), user),
        ),
      );
    }
    final Set<String> cachedNames = cached
        .map((CachedUserProfile profile) => profile.username.toLowerCase())
        .toSet();
    final List<String> missing = requested
        .where((String name) => !cachedNames.contains(name))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      final Set<String> expected = missing.toSet();
      final List<UserSummary> loaded = (await _api.getUsersByUsernames(missing))
          .where(
            (MattermostUserDto user) =>
                user.id.isNotEmpty &&
                expected.contains(user.username.toLowerCase()),
          )
          .map(mapUserSummary)
          .toList(growable: false);
      await _cacheUsers(loaded);
      usersByUsername.addEntries(
        loaded.map(
          (UserSummary user) =>
              MapEntry<String, UserSummary>(user.username.toLowerCase(), user),
        ),
      );
    }
    return requested
        .map((String username) => usersByUsername[username])
        .whereType<UserSummary>()
        .toList(growable: false);
  }

  @override
  Future<UserProfile> getProfile(
    String userId, {
    UserFreshness freshness = UserFreshness.fresh,
  }) async {
    if (userId.isEmpty) throw ArgumentError.value(userId, 'userId');
    final List<Object> result = await Future.wait<Object>(<Future<Object>>[
      _api.getUserById(userId),
      _api.getUserStatus(userId),
    ]);
    final MattermostUserDto user = result[0] as MattermostUserDto;
    final MattermostUserStatusDto status = result[1] as MattermostUserStatusDto;
    if (user.id != userId) {
      throw FormatException(
        'Mattermost returned profile ${user.id} when $userId was requested',
      );
    }
    return mapUserProfile(user: user, status: status);
  }

  @override
  Future<UserAvatar> loadAvatar({
    required String userId,
    required int profileImageUpdatedAt,
  }) async {
    if (userId.isEmpty) throw ArgumentError.value(userId, 'userId');
    final String key = _profileImageUri(
      accountScopeId: _accountScopeId,
      userId: userId,
      profileImageUpdatedAt: profileImageUpdatedAt,
    ).toString();
    final Future<UserAvatar>? existing = _avatarInFlight[key];
    if (existing != null) return existing;
    final Future<UserAvatar> request = _loadAvatar(
      key: key,
      userId: userId,
      profileImageUpdatedAt: profileImageUpdatedAt,
    );
    _avatarInFlight[key] = request;
    try {
      return await request;
    } finally {
      if (identical(_avatarInFlight[key], request)) _avatarInFlight.remove(key);
    }
  }

  Future<List<UserSummary>> _loadIds(
    List<String> userIds, {
    required bool cacheResult,
  }) async {
    final Set<String> requested = userIds.toSet();
    final List<UserSummary> loaded = (await _api.getUsersByIds(userIds))
        .where(
          (MattermostUserDto user) =>
              user.id.isNotEmpty && requested.contains(user.id),
        )
        .map(mapUserSummary)
        .toList(growable: false);
    if (cacheResult) await _cacheUsers(loaded);
    final Map<String, UserSummary> byId = <String, UserSummary>{
      for (final UserSummary user in loaded) user.id: user,
    };
    return userIds
        .map((String id) => byId[id])
        .whereType<UserSummary>()
        .toList(growable: false);
  }

  Future<void> _cacheUsers(List<UserSummary> users) async {
    if (users.isEmpty) return;
    final DateTime expiresAt = _now().toUtc().add(cacheLifetime);
    await _cache.upsertAll(
      accountId: _accountScopeId,
      profiles: users
          .where((UserSummary user) => user.id.isNotEmpty)
          .map((UserSummary user) => cacheUserSummary(user, expiresAt))
          .toList(growable: false),
    );
  }

  Future<UserAvatar> _loadAvatar({
    required String key,
    required String userId,
    required int profileImageUpdatedAt,
  }) async {
    Uint8List? cached;
    try {
      cached = await _avatarCache.read(key);
    } on Object {
      // Cache availability is only an optimization.
    }
    if (cached != null && cached.isNotEmpty) return UserAvatar(bytes: cached);
    final MattermostImageDto response = await _api.getUserProfileImage(
      userId: userId,
      lastPictureUpdate: profileImageUpdatedAt,
    );
    if (response.bytes.isEmpty) {
      throw const FormatException('Profile image response was empty');
    }
    try {
      await _avatarCache.write(
        key: key,
        bytes: response.bytes,
        contentType: response.contentType,
      );
    } on Object {
      // A temporary cache failure must not hide downloaded content.
    }
    return UserAvatar(bytes: response.bytes, contentType: response.contentType);
  }

  static bool _isFresh(DateTime expiresAt, DateTime now) =>
      expiresAt.toUtc().isAfter(now);

  static List<String> _uniqueNonEmpty(Iterable<String> values) => values
      .where((String value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);

  static List<String> _uniqueNormalizedUsernames(Iterable<String> values) =>
      values
          .map((String value) => value.trim().toLowerCase())
          .where((String value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false);

  static List<UserSummary> _orderByUsername(
    List<String> requested,
    List<UserSummary> users,
  ) {
    final Map<String, UserSummary> byUsername = <String, UserSummary>{
      for (final UserSummary user in users) user.username.toLowerCase(): user,
    };
    return requested
        .map((String username) => byUsername[username])
        .whereType<UserSummary>()
        .toList(growable: false);
  }
}

Uri _profileImageUri({
  required String accountScopeId,
  required String userId,
  required int profileImageUpdatedAt,
}) {
  final Uri serverUrl = Uri.parse(
    accountScopeId.endsWith('/') ? accountScopeId : '$accountScopeId/',
  );
  return serverUrl
      .resolve('api/v4/users/$userId/image')
      .replace(
        queryParameters: profileImageUpdatedAt > 0
            ? <String, String>{'_': '$profileImageUpdatedAt'}
            : null,
      );
}
