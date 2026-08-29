import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/database/app_database.dart' as db;
import 'package:mattermost_flutter/src/features/users/data/cached_user_profile_api.dart';
import 'package:mattermost_flutter/src/features/users/data/user_profile_cache.dart';

void main() {
  late db.AppDatabase database;
  late DriftUserProfileCache cache;
  final DateTime now = DateTime.utc(2026, 8, 27, 10);

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    cache = DriftUserProfileCache(database);
  });

  tearDown(() => database.close());

  test(
    'loads missing users in one batch and then reads them from SQL',
    () async {
      final _UsersApi api = _UsersApi(<String, MattermostUserDto>{
        'ada': const MattermostUserDto(
          id: 'ada',
          username: 'ada.login',
          firstName: 'Ada',
          lastName: 'Lovelace',
          nickname: 'Enchantress of Numbers',
          position: 'Mathematician',
          email: 'ada@example.com',
          lastPictureUpdate: 42,
        ),
        'grace': const MattermostUserDto(
          id: 'grace',
          username: 'grace.login',
          firstName: 'Grace',
          lastName: 'Hopper',
        ),
      });
      final CachedUserProfileApi cachedApi = CachedUserProfileApi(
        delegate: api,
        cache: cache,
        accountId: 'https://chat.example.com',
        now: () => now,
      );

      final List<MattermostUserDto> first = await cachedApi.getUsersByIds(
        <String>['grace', 'ada'],
      );
      final List<MattermostUserDto> second = await cachedApi.getUsersByIds(
        <String>['ada', 'grace'],
      );

      expect(api.requests, <List<String>>[
        <String>['grace', 'ada'],
      ]);
      expect(first.map((MattermostUserDto user) => user.id), <String>[
        'grace',
        'ada',
      ]);
      expect(second.first.username, 'ada.login');
      expect(second.first.firstName, 'Ada');
      expect(second.first.lastName, 'Lovelace');
      expect(second.first.nickname, 'Enchantress of Numbers');
      expect(second.first.position, 'Mathematician');
      expect(second.first.email, 'ada@example.com');
      expect(second.first.lastPictureUpdate, 42);
      final List<CachedUserProfile> stored = await cache.getByIds(
        accountId: 'https://chat.example.com',
        userIds: <String>['ada', 'grace'],
      );
      expect(stored, hasLength(2));
      expect(
        stored
            .map(
              (CachedUserProfile profile) =>
                  profile.expiresAt.millisecondsSinceEpoch,
            )
            .toSet(),
        <int>{now.add(const Duration(days: 7)).millisecondsSinceEpoch},
      );
    },
  );

  test(
    'fetches only missing or expired IDs and overwrites expired data',
    () async {
      await cache.upsertAll(
        accountId: 'server-a',
        profiles: <CachedUserProfile>[
          CachedUserProfile(
            userId: 'fresh',
            firstName: 'Fresh',
            lastName: 'User',
            username: 'fresh',
            expiresAt: now.add(const Duration(minutes: 1)),
          ),
          CachedUserProfile(
            userId: 'expired',
            firstName: 'Old',
            lastName: 'Name',
            username: 'old',
            expiresAt: now,
          ),
        ],
      );
      final _UsersApi api = _UsersApi(<String, MattermostUserDto>{
        'expired': const MattermostUserDto(
          id: 'expired',
          username: 'new',
          firstName: 'New',
          lastName: 'Name',
        ),
        'missing': const MattermostUserDto(
          id: 'missing',
          username: 'missing',
          firstName: 'Missing',
        ),
      });
      final CachedUserProfileApi cachedApi = CachedUserProfileApi(
        delegate: api,
        cache: cache,
        accountId: 'server-a',
        now: () => now,
      );

      final List<MattermostUserDto> users = await cachedApi.getUsersByIds(
        <String>['fresh', 'expired', 'missing'],
      );

      expect(api.requests.single, <String>['expired', 'missing']);
      expect(users.map((MattermostUserDto user) => user.firstName), <String>[
        'Fresh',
        'New',
        'Missing',
      ]);
      expect(
        (await cache.getById(
          accountId: 'server-a',
          userId: 'expired',
        ))?.username,
        'new',
      );
    },
  );

  test(
    'scopes cached profiles by account and does not serve expired on error',
    () async {
      await cache.upsertAll(
        accountId: 'server-a',
        profiles: <CachedUserProfile>[
          CachedUserProfile(
            userId: 'ada',
            firstName: 'Ada',
            lastName: 'Old',
            username: 'ada',
            expiresAt: now.subtract(const Duration(seconds: 1)),
          ),
        ],
      );
      final _UsersApi api = _UsersApi(<String, MattermostUserDto>{})
        ..error = StateError('offline');
      final CachedUserProfileApi cachedApi = CachedUserProfileApi(
        delegate: api,
        cache: cache,
        accountId: 'server-b',
        now: () => now,
      );

      await expectLater(
        cachedApi.getUsersByIds(<String>['ada']),
        throwsA(isA<StateError>()),
      );
      expect(api.requests.single, <String>['ada']);
    },
  );

  test('single profile lookup always bypasses the batch cache', () async {
    await cache.upsertAll(
      accountId: 'server-a',
      profiles: <CachedUserProfile>[
        CachedUserProfile(
          userId: 'ada',
          firstName: 'Ada',
          lastName: 'Lovelace',
          username: 'ada',
          expiresAt: now.add(const Duration(days: 7)),
        ),
      ],
    );
    final _UsersApi api = _UsersApi(<String, MattermostUserDto>{
      'ada': const MattermostUserDto(
        id: 'ada',
        username: 'ada',
        position: 'Fresh position',
        email: 'fresh@example.com',
      ),
    });
    final CachedUserProfileApi cachedApi = CachedUserProfileApi(
      delegate: api,
      cache: cache,
      accountId: 'server-a',
      now: () => now,
    );

    final MattermostUserDto user = await cachedApi.getUserById('ada');

    expect(api.singleRequests, <String>['ada']);
    expect(api.requests, isEmpty);
    expect(user.position, 'Fresh position');
    expect(user.email, 'fresh@example.com');
  });

  test('resolves usernames from cache and refreshes known stale IDs', () async {
    await cache.upsertAll(
      accountId: 'server-a',
      profiles: <CachedUserProfile>[
        CachedUserProfile(
          userId: 'fresh-id',
          firstName: 'Fresh',
          lastName: 'User',
          username: 'Fresh.User',
          expiresAt: now.add(const Duration(minutes: 1)),
        ),
        CachedUserProfile(
          userId: 'stale-id',
          firstName: 'Old',
          lastName: 'Name',
          username: 'stale',
          expiresAt: now,
        ),
      ],
    );
    final _UsersApi api = _UsersApi(<String, MattermostUserDto>{
      'stale-id': const MattermostUserDto(
        id: 'stale-id',
        username: 'stale',
        firstName: 'New',
        lastName: 'Name',
      ),
    });
    final CachedUserProfileApi cachedApi = CachedUserProfileApi(
      delegate: api,
      cache: cache,
      accountId: 'server-a',
      now: () => now,
    );

    final List<MattermostUserDto> users = await cachedApi.getUsersByUsernames(
      <String>['fresh.user', 'stale'],
    );

    expect(users.map((MattermostUserDto user) => user.firstName), <String>[
      'Fresh',
      'New',
    ]);
    expect(api.requests, <List<String>>[
      <String>['stale-id'],
    ]);
    expect(api.usernameRequests, isEmpty);
  });

  test(
    'loads uncached usernames and leaves missing users unresolved',
    () async {
      final _UsersApi api = _UsersApi(<String, MattermostUserDto>{
        'ada-id': const MattermostUserDto(
          id: 'ada-id',
          username: 'ada',
          firstName: 'Ada',
        ),
      });
      final CachedUserProfileApi cachedApi = CachedUserProfileApi(
        delegate: api,
        cache: cache,
        accountId: 'server-a',
        now: () => now,
      );

      final List<MattermostUserDto> users = await cachedApi.getUsersByUsernames(
        <String>['ada', 'does-not-exist'],
      );

      expect(users.map((MattermostUserDto user) => user.username), <String>[
        'ada',
      ]);
      expect(api.usernameRequests.single, <String>['ada', 'does-not-exist']);
      expect(
        (await cache.getByUsernames(
          accountId: 'server-a',
          usernames: <String>['ADA'],
        )).single.userId,
        'ada-id',
      );
    },
  );
}

final class _UsersApi implements MattermostApi {
  _UsersApi(this.users);

  final Map<String, MattermostUserDto> users;
  final List<List<String>> requests = <List<String>>[];
  final List<String> singleRequests = <String>[];
  final List<List<String>> usernameRequests = <List<String>>[];
  Object? error;

  @override
  Future<List<MattermostUserDto>> getUsersByIds(List<String> userIds) async {
    requests.add(List<String>.of(userIds));
    if (error case final Object error) throw error;
    return userIds
        .map((String id) => users[id])
        .whereType<MattermostUserDto>()
        .toList(growable: false);
  }

  @override
  Future<MattermostUserDto> getUserById(String userId) async {
    singleRequests.add(userId);
    if (error case final Object error) throw error;
    final MattermostUserDto? user = users[userId];
    if (user == null) throw StateError('missing user');
    return user;
  }

  @override
  Future<List<MattermostUserDto>> getUsersByUsernames(
    List<String> usernames,
  ) async {
    usernameRequests.add(List<String>.of(usernames));
    if (error case final Object error) throw error;
    final Set<String> requested = usernames
        .map((String username) => username.toLowerCase())
        .toSet();
    return users.values
        .where(
          (MattermostUserDto user) =>
              requested.contains(user.username.toLowerCase()),
        )
        .toList(growable: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
