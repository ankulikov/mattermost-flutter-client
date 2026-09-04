import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/data/repositories/mattermost_postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';

void main() {
  final AuthSession session = AuthSession(
    serverUrl: Uri.parse('https://chat.example'),
    userId: 'me',
    username: 'me',
  );

  test(
    'uses one exact preference per reference and batches writes at 100',
    () async {
      final _PreferencesApi api = _PreferencesApi();
      final MattermostPostponedRepository repository =
          MattermostPostponedRepository(api: api);
      final List<PostponedReference> references =
          List<PostponedReference>.generate(
            101,
            (int index) => PostponedReference(
              postId: 'post-$index',
              kind: PostponedReferenceKind.post,
              addedAt: DateTime.fromMillisecondsSinceEpoch(index),
            ),
          );

      await repository.save(session: session, references: references);
      await repository.remove(session: session, references: references);

      expect(api.saved.map((it) => it.length), <int>[100, 1]);
      expect(api.deleted.map((it) => it.length), <int>[100, 1]);
      final MattermostPreferenceDto first = api.saved.first.first;
      expect(first.category, MattermostPostponedRepository.category);
      expect(first.name, 'post-0');
      expect(
        (jsonDecode(first.value) as Map<String, Object?>)['post_id'],
        'post-0',
      );
    },
  );

  test('ignores malformed and mismatched postponed preferences', () async {
    final _PreferencesApi api = _PreferencesApi(
      preferences: <MattermostPreferenceDto>[
        const MattermostPreferenceDto(
          userId: 'me',
          category: 'postponed_messages',
          name: 'post-1',
          value: '{"v":1,"post_id":"post-1","added_at":1,"kind":"post"}',
        ),
        const MattermostPreferenceDto(
          userId: 'me',
          category: 'postponed_messages',
          name: 'post-2',
          value: '{invalid',
        ),
        const MattermostPreferenceDto(
          userId: 'me',
          category: 'postponed_messages',
          name: 'post-3',
          value: '{"post_id":"other","added_at":1,"kind":"post"}',
        ),
      ],
    );

    final PostponedReferencesSnapshot result =
        await MattermostPostponedRepository(api: api).load(session: session);

    expect(result.references.map((it) => it.postId), <String>['post-1']);
  });

  test(
    'treats the server missing-category response as an empty queue',
    () async {
      final _PreferencesApi api = _PreferencesApi(
        getError: DioException(
          requestOptions: RequestOptions(
            path: '/users/me/preferences/postponed_messages',
          ),
          response: Response<Object?>(
            requestOptions: RequestOptions(
              path: '/users/me/preferences/postponed_messages',
            ),
            statusCode: 404,
            data: const <String, Object?>{
              'id': 'api.preference.preferences_category.get.app_error',
            },
          ),
        ),
      );

      final PostponedReferencesSnapshot result =
          await MattermostPostponedRepository(api: api).load(session: session);

      expect(result.references, isEmpty);
    },
  );
}

final class _PreferencesApi extends Fake implements MattermostApi {
  _PreferencesApi({
    this.preferences = const <MattermostPreferenceDto>[],
    this.getError,
  });

  final List<MattermostPreferenceDto> preferences;
  final Object? getError;
  final List<List<MattermostPreferenceDto>> saved =
      <List<MattermostPreferenceDto>>[];
  final List<List<MattermostPreferenceDto>> deleted =
      <List<MattermostPreferenceDto>>[];

  @override
  Future<List<MattermostPreferenceDto>> getPreferencesByCategory({
    required String userId,
    required String category,
  }) async {
    if (getError != null) throw getError!;
    return preferences;
  }

  @override
  Future<void> savePreferences({
    required String userId,
    required List<MattermostPreferenceDto> preferences,
  }) async => saved.add(preferences);

  @override
  Future<void> deletePreferences({
    required String userId,
    required List<MattermostPreferenceDto> preferences,
  }) async => deleted.add(preferences);
}
