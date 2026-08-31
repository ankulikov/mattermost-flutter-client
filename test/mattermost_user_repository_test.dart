import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/cache/avatar_cache.dart';
import 'package:mattermost_flutter/src/data/database/app_database.dart' as db;
import 'package:mattermost_flutter/src/data/database/user_profile_cache_dao.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_user_repository.dart';

void main() {
  late db.AppDatabase database;
  late DriftUserProfileCache cache;
  final DateTime now = DateTime.utc(2026, 8, 30, 12);

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    cache = DriftUserProfileCache(database);
  });
  tearDown(() => database.close());

  test(
    'uses one batch for missing summaries and reuses fresh cache rows',
    () async {
      final _UserApi api = _UserApi();
      final MattermostUserRepository repository = MattermostUserRepository(
        api: api,
        cache: cache,
        avatarCache: const _NoopAvatarCache(),
        accountScopeId: 'https://chat.example.com::me',
        now: () => now,
      );

      expect(
        (await repository.getUsers(<String>[
          'ada',
          'grace',
        ])).map((user) => user.fullName),
        <String>['Ada Lovelace', 'Grace Hopper'],
      );
      await repository.getUsers(<String>['grace', 'ada']);

      expect(api.idBatches, <List<String>>[
        <String>['ada', 'grace'],
      ]);
    },
  );

  test('does not serve expired summaries after a refresh failure', () async {
    await cache.upsertAll(
      accountId: 'scope',
      profiles: <CachedUserProfile>[
        CachedUserProfile(
          userId: 'ada',
          firstName: 'Old',
          lastName: 'Profile',
          username: 'ada',
          expiresAt: now.subtract(const Duration(seconds: 1)),
        ),
      ],
    );
    final _UserApi api = _UserApi(failIds: true);
    final MattermostUserRepository repository = MattermostUserRepository(
      api: api,
      cache: cache,
      avatarCache: const _NoopAvatarCache(),
      accountScopeId: 'scope',
      now: () => now,
    );

    await expectLater(repository.getUsers(<String>['ada']), throwsStateError);
  });

  test('resolves usernames case-insensitively from the scoped cache', () async {
    await cache.upsertAll(
      accountId: 'scope-a',
      profiles: <CachedUserProfile>[
        CachedUserProfile(
          userId: 'ada',
          firstName: 'Ada',
          lastName: 'Lovelace',
          username: 'Ada',
          expiresAt: now.add(const Duration(days: 1)),
        ),
      ],
    );
    final _UserApi api = _UserApi();
    final MattermostUserRepository repository = MattermostUserRepository(
      api: api,
      cache: cache,
      avatarCache: const _NoopAvatarCache(),
      accountScopeId: 'scope-a',
      now: () => now,
    );

    final user = await repository.getUserByUsername('aDa');
    expect(user?.fullName, 'Ada Lovelace');
    expect(api.usernameBatches, isEmpty);
  });

  test(
    'loads a fresh profile and presence without using the batch cache',
    () async {
      final _UserApi api = _UserApi();
      final MattermostUserRepository repository = MattermostUserRepository(
        api: api,
        cache: cache,
        avatarCache: const _NoopAvatarCache(),
        accountScopeId: 'scope',
        now: () => now,
      );

      final profile = await repository.getProfile('ada');
      expect(profile.fullName, 'Ada Lovelace');
      expect(profile.presence.name, 'online');
      expect(api.idBatches, isEmpty);
      expect(api.requestedProfileId, 'ada');
      expect(api.requestedStatusId, 'ada');
    },
  );

  test('loads an avatar for an account-scoped cache key', () async {
    final _UserApi api = _UserApi();
    final _RecordingAvatarCache avatarCache = _RecordingAvatarCache();
    final MattermostUserRepository repository = MattermostUserRepository(
      api: api,
      cache: cache,
      avatarCache: avatarCache,
      accountScopeId: 'https://chat.example.com|user:me',
      now: () => now,
    );

    final avatar = await repository.loadAvatar(
      userId: 'ada',
      profileImageUpdatedAt: 42,
    );

    expect(avatar.bytes, <int>[1, 2, 3]);
    expect(api.requestedAvatar, ('ada', 42));
    expect(
      avatarCache.writtenKey,
      'avatar|account:https%3A%2F%2Fchat.example.com%7Cuser%3Ame'
      '|user:ada|updated:42',
    );
  });
}

final class _NoopAvatarCache implements UserAvatarCache {
  const _NoopAvatarCache();

  @override
  Future<Uint8List?> read(String key) async => null;

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> write({
    required String key,
    required Uint8List bytes,
    required String? contentType,
  }) async {}
}

final class _RecordingAvatarCache implements UserAvatarCache {
  String? writtenKey;

  @override
  Future<Uint8List?> read(String key) async => null;

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> write({
    required String key,
    required Uint8List bytes,
    required String? contentType,
  }) async {
    writtenKey = key;
  }
}

final class _UserApi implements MattermostApi {
  _UserApi({this.failIds = false});

  final bool failIds;
  final List<List<String>> idBatches = <List<String>>[];
  final List<List<String>> usernameBatches = <List<String>>[];
  String? requestedProfileId;
  String? requestedStatusId;
  (String, int)? requestedAvatar;

  @override
  Future<List<MattermostUserDto>> getUsersByIds(List<String> userIds) async {
    idBatches.add(List<String>.of(userIds));
    if (failIds) throw StateError('offline');
    return userIds.map(_user).toList(growable: false);
  }

  @override
  Future<List<MattermostUserDto>> getUsersByUsernames(
    List<String> usernames,
  ) async {
    usernameBatches.add(List<String>.of(usernames));
    return usernames.map(_user).toList(growable: false);
  }

  @override
  Future<MattermostUserDto> getUserById(String userId) async {
    requestedProfileId = userId;
    return _user(userId);
  }

  @override
  Future<MattermostUserStatusDto> getUserStatus(String userId) async {
    requestedStatusId = userId;
    return MattermostUserStatusDto(userId: userId, status: 'online');
  }

  @override
  Future<MattermostImageDto> getUserProfileImage({
    required String userId,
    int lastPictureUpdate = 0,
  }) async {
    requestedAvatar = (userId, lastPictureUpdate);
    return MattermostImageDto(
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      contentType: 'image/png',
    );
  }

  static MattermostUserDto _user(String id) => switch (id.toLowerCase()) {
    'ada' => const MattermostUserDto(
      id: 'ada',
      username: 'ada',
      firstName: 'Ada',
      lastName: 'Lovelace',
    ),
    'grace' => const MattermostUserDto(
      id: 'grace',
      username: 'grace',
      firstName: 'Grace',
      lastName: 'Hopper',
    ),
    _ => MattermostUserDto(id: id, username: id),
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
