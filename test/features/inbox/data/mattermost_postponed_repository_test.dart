import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/data/repositories/mattermost_postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';

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

  test(
    'reports a middle save batch as partial instead of silently claiming 250 references',
    () async {
      final _PreferencesApi api = _PreferencesApi(saveFailureCalls: <int>{2});
      final MattermostPostponedRepository repository =
          MattermostPostponedRepository(api: api);
      final List<PostponedReference> references = _references(250);

      final PostponedBatchOutcome outcome = await repository.saveWithOutcome(
        session: session,
        references: references,
      );

      expect(outcome.requiresReconciliation, isTrue);
      expect(outcome.requested, references);
      expect(outcome.confirmed, references.take(100));
      expect(api.saved.map((it) => it.length), <int>[100]);
      expect(api.serverReferences, hasLength(100));
    },
  );

  test(
    'reports a partial remove and a retry converges to authoritative preferences',
    () async {
      final _PreferencesApi api = _PreferencesApi(deleteFailureCalls: <int>{2});
      final MattermostPostponedRepository repository =
          MattermostPostponedRepository(api: api);
      final List<PostponedReference> references = _references(201);
      api.seed(references);

      final PostponedBatchOutcome first = await repository.removeWithOutcome(
        session: session,
        references: references,
      );
      expect(first.requiresReconciliation, isTrue);
      expect(first.confirmed, references.take(100));
      expect(
        api.serverReferences.map((PostponedReference it) => it.postId),
        references.skip(100).map((PostponedReference it) => it.postId),
      );

      api.deleteFailureCalls.clear();
      final PostponedBatchOutcome retry = await repository.removeWithOutcome(
        session: session,
        references: references,
      );
      expect(retry.isFullyConfirmed, isTrue);
      expect(api.serverReferences, isEmpty);
    },
  );

  test(
    'deduplicates repeated references without changing their exact payload',
    () async {
      final _PreferencesApi api = _PreferencesApi();
      final MattermostPostponedRepository repository =
          MattermostPostponedRepository(api: api);
      final PostponedReference thread = PostponedReference(
        postId: 'root',
        kind: PostponedReferenceKind.thread,
        targetPostId: 'reply',
        addedAt: DateTime.utc(2026, 9, 27),
      );

      final PostponedBatchOutcome outcome = await repository.saveWithOutcome(
        session: session,
        references: <PostponedReference>[thread, thread],
      );

      expect(outcome.requested, <PostponedReference>[thread]);
      expect(api.saved.single, hasLength(1));
      final Map<String, Object?> value =
          jsonDecode(api.saved.single.single.value) as Map<String, Object?>;
      expect(value['kind'], 'thread');
      expect(value['target_post_id'], 'reply');
      expect(value['added_at'], thread.addedAt.millisecondsSinceEpoch);
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
    'ignores oversized postponed preference values before decoding',
    () async {
      final _PreferencesApi api = _PreferencesApi(
        preferences: <MattermostPreferenceDto>[
          MattermostPreferenceDto(
            userId: 'me',
            category: MattermostPostponedRepository.category,
            name: 'post-oversized',
            value: 'x' * 4097,
          ),
        ],
      );

      final PostponedReferencesSnapshot result =
          await MattermostPostponedRepository(api: api).load(session: session);

      expect(result.references, isEmpty);
    },
  );

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

List<PostponedReference> _references(int count) =>
    List<PostponedReference>.generate(
      count,
      (int index) => PostponedReference(
        postId: 'post-$index',
        kind: PostponedReferenceKind.post,
        addedAt: DateTime.fromMillisecondsSinceEpoch(index),
      ),
    );

final class _PreferencesApi extends Fake implements MattermostApi {
  _PreferencesApi({
    this.preferences = const <MattermostPreferenceDto>[],
    this.getError,
    Set<int> saveFailureCalls = const <int>{},
    Set<int> deleteFailureCalls = const <int>{},
  }) : saveFailureCalls = Set<int>.of(saveFailureCalls),
       deleteFailureCalls = Set<int>.of(deleteFailureCalls);

  final List<MattermostPreferenceDto> preferences;
  final Object? getError;
  final Set<int> saveFailureCalls;
  final Set<int> deleteFailureCalls;
  final List<List<MattermostPreferenceDto>> saved =
      <List<MattermostPreferenceDto>>[];
  final List<List<MattermostPreferenceDto>> deleted =
      <List<MattermostPreferenceDto>>[];
  final Map<String, PostponedReference> _serverReferences =
      <String, PostponedReference>{};
  var _saveCalls = 0;
  var _deleteCalls = 0;

  Iterable<PostponedReference> get serverReferences => _serverReferences.values;

  void seed(Iterable<PostponedReference> references) {
    for (final PostponedReference reference in references) {
      _serverReferences[reference.canonicalId] = reference;
    }
  }

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
  }) async {
    _saveCalls++;
    if (saveFailureCalls.contains(_saveCalls)) throw StateError('failed');
    saved.add(preferences);
    for (final MattermostPreferenceDto preference in preferences) {
      final Map<String, Object?> value =
          jsonDecode(preference.value) as Map<String, Object?>;
      _serverReferences[preference.name] = PostponedReference(
        postId: value['post_id']! as String,
        kind: value['kind'] == 'thread'
            ? PostponedReferenceKind.thread
            : PostponedReferenceKind.post,
        targetPostId: value['target_post_id'] as String?,
        addedAt: DateTime.fromMillisecondsSinceEpoch(value['added_at']! as int),
      );
    }
  }

  @override
  Future<void> deletePreferences({
    required String userId,
    required List<MattermostPreferenceDto> preferences,
  }) async {
    _deleteCalls++;
    if (deleteFailureCalls.contains(_deleteCalls)) throw StateError('failed');
    deleted.add(preferences);
    for (final MattermostPreferenceDto preference in preferences) {
      _serverReferences.remove(preference.name);
    }
  }
}
