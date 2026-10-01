import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/data/repositories/mattermost_viewed_channel_posts_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/viewed_channel_posts.dart';

void main() {
  final AuthSession session = AuthSession(
    serverUrl: Uri.parse('https://chat.example'),
    userId: 'me',
    username: 'me',
  );

  test('loads only valid account-scoped content-free post id sets', () async {
    final _PreferencesApi api = _PreferencesApi(
      preferences: const <MattermostPreferenceDto>[
        MattermostPreferenceDto(
          userId: 'me',
          category: MattermostViewedChannelPostsRepository.category,
          name: 'channel',
          value:
              '{"v":1,"channel_id":"channel","post_ids":["one","two","one"]}',
        ),
        MattermostPreferenceDto(
          userId: 'someone-else',
          category: MattermostViewedChannelPostsRepository.category,
          name: 'channel',
          value: '{"v":1,"channel_id":"channel","post_ids":["private"]}',
        ),
        MattermostPreferenceDto(
          userId: 'me',
          category: MattermostViewedChannelPostsRepository.category,
          name: 'bad',
          value: '{invalid',
        ),
      ],
    );

    final ViewedChannelPostsSnapshot snapshot =
        await MattermostViewedChannelPostsRepository(
          api: api,
        ).load(session: session);

    expect(snapshot.forChannel('channel'), <String>{'one', 'two'});
    expect(snapshot.forChannel('bad'), isEmpty);
    expect(api.loadedUserId, 'me');
  });

  test('merges ids without dropping the existing viewed set', () async {
    final _PreferencesApi api = _PreferencesApi(
      preferences: const <MattermostPreferenceDto>[
        MattermostPreferenceDto(
          userId: 'me',
          category: MattermostViewedChannelPostsRepository.category,
          name: 'channel',
          value: '{"v":1,"channel_id":"channel","post_ids":["old"]}',
        ),
      ],
    );

    await MattermostViewedChannelPostsRepository(
      api: api,
    ).add(session: session, channelId: 'channel', postId: 'new');

    final Map<String, Object?> value =
        jsonDecode(api.saved.single.single.value) as Map<String, Object?>;
    expect(value['post_ids'], <Object?>['new', 'old']);
  });

  test('serializes concurrent additions without losing either id', () async {
    final _PreferencesApi api = _PreferencesApi();
    final MattermostViewedChannelPostsRepository repository =
        MattermostViewedChannelPostsRepository(api: api);

    await Future.wait(<Future<void>>[
      repository.add(session: session, channelId: 'channel', postId: 'one'),
      repository.add(session: session, channelId: 'channel', postId: 'two'),
    ]);

    final Map<String, Object?> value =
        jsonDecode(api.saved.last.single.value) as Map<String, Object?>;
    expect(value['post_ids'], <Object?>['one', 'two']);
  });

  test(
    'rejects an oversized set without dropping prior ids or writing',
    () async {
      final List<String> existing = List<String>.generate(
        665,
        (int index) => 'post-${index.toString().padLeft(22, '0')}',
      );
      final _PreferencesApi api = _PreferencesApi(
        preferences: <MattermostPreferenceDto>[
          MattermostPreferenceDto(
            userId: 'me',
            category: MattermostViewedChannelPostsRepository.category,
            name: 'channel',
            value: jsonEncode(<String, Object?>{
              'v': 1,
              'channel_id': 'channel',
              'post_ids': existing,
            }),
          ),
        ],
      );

      await expectLater(
        MattermostViewedChannelPostsRepository(api: api).add(
          session: session,
          channelId: 'channel',
          postId: 'required-new-post',
        ),
        throwsStateError,
      );

      expect(api.saved, isEmpty);
      final Map<String, Object?> original =
          jsonDecode(api.preferences.single.value) as Map<String, Object?>;
      expect(original['post_ids'], existing);
    },
  );

  test('deletes the exact channel preference', () async {
    final _PreferencesApi api = _PreferencesApi();

    await MattermostViewedChannelPostsRepository(
      api: api,
    ).removeChannel(session: session, channelId: 'channel');

    final MattermostPreferenceDto deleted = api.deleted.single.single;
    expect(deleted.userId, 'me');
    expect(deleted.category, MattermostViewedChannelPostsRepository.category);
    expect(deleted.name, 'channel');
  });
}

final class _PreferencesApi extends Fake implements MattermostApi {
  _PreferencesApi({List<MattermostPreferenceDto> preferences = const []})
    : preferences = List<MattermostPreferenceDto>.of(preferences);

  final List<MattermostPreferenceDto> preferences;
  String? loadedUserId;
  final List<List<MattermostPreferenceDto>> saved =
      <List<MattermostPreferenceDto>>[];
  final List<List<MattermostPreferenceDto>> deleted =
      <List<MattermostPreferenceDto>>[];

  @override
  Future<List<MattermostPreferenceDto>> getPreferencesByCategory({
    required String userId,
    required String category,
  }) async {
    loadedUserId = userId;
    return preferences;
  }

  @override
  Future<void> savePreferences({
    required String userId,
    required List<MattermostPreferenceDto> preferences,
  }) async {
    final List<MattermostPreferenceDto> copy = List.of(preferences);
    saved.add(copy);
    for (final MattermostPreferenceDto preference in copy) {
      this.preferences.removeWhere(
        (MattermostPreferenceDto current) =>
            current.userId == preference.userId &&
            current.category == preference.category &&
            current.name == preference.name,
      );
      this.preferences.add(preference);
    }
  }

  @override
  Future<void> deletePreferences({
    required String userId,
    required List<MattermostPreferenceDto> preferences,
  }) async {
    final List<MattermostPreferenceDto> copy = List.of(preferences);
    deleted.add(copy);
    for (final MattermostPreferenceDto preference in copy) {
      this.preferences.removeWhere(
        (MattermostPreferenceDto current) =>
            current.userId == preference.userId &&
            current.category == preference.category &&
            current.name == preference.name,
      );
    }
  }
}
