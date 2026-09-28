import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_settings.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_settings_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/use_cases/reactivate_postponed_thread.dart';

void main() {
  final AuthSession session = AuthSession(
    serverUrl: Uri.parse('https://chat.example.test'),
    userId: 'me',
    username: 'me',
  );
  final PostponedReference reference = PostponedReference(
    postId: 'root',
    kind: PostponedReferenceKind.thread,
    addedAt: DateTime.utc(2026, 9, 26),
  );

  test(
    'follows, removes the exact preference, then reports reactivation',
    () async {
      final List<String> calls = <String>[];
      final _Threads threads = _Threads(calls: calls);
      final _Postponed postponed = _Postponed(calls: calls);
      final PostponedThreadReactivationResult result = await _workflow(
        postponed: postponed,
        threads: threads,
      )(session: session, teamId: 'team', reference: reference);

      expect(result.status, PostponedThreadReactivationStatus.reactivated);
      expect(calls, <String>['isFollowing', 'follow', 'remove']);
      expect(postponed.removed, <PostponedReference>[reference]);
    },
  );

  test(
    'leaves the item postponed when no explicit server setting enables it',
    () async {
      final List<String> calls = <String>[];
      final _Threads threads = _Threads(calls: calls);
      final _Postponed postponed = _Postponed(calls: calls);
      final PostponedThreadReactivationResult result = await _workflow(
        settings: const InboxSettingsSnapshot.defaults(),
        postponed: postponed,
        threads: threads,
      )(session: session, teamId: 'team', reference: reference);

      expect(
        result.status,
        PostponedThreadReactivationStatus.disabledBySettings,
      );
      expect(calls, isEmpty);
    },
  );

  test('leaves the item postponed when the setting is disabled', () async {
    final List<String> calls = <String>[];
    final _Threads threads = _Threads(calls: calls);
    final _Postponed postponed = _Postponed(calls: calls);
    final PostponedThreadReactivationResult result = await _workflow(
      settings: _settings(reactivateOnMention: false),
      postponed: postponed,
      threads: threads,
    )(session: session, teamId: 'team', reference: reference);

    expect(result.status, PostponedThreadReactivationStatus.disabledBySettings);
    expect(calls, isEmpty);
  });

  test('does not follow an already followed thread', () async {
    final List<String> calls = <String>[];
    final _Threads threads = _Threads(calls: calls, following: true);
    final PostponedThreadReactivationResult result = await _workflow(
      postponed: _Postponed(calls: calls),
      threads: threads,
    )(session: session, teamId: 'team', reference: reference);

    expect(result.status, PostponedThreadReactivationStatus.reactivated);
    expect(calls, <String>['isFollowing', 'remove']);
  });

  test(
    'follow failure preserves the preference and never removes it',
    () async {
      final List<String> calls = <String>[];
      final _Postponed postponed = _Postponed(calls: calls);
      final PostponedThreadReactivationResult result = await _workflow(
        postponed: postponed,
        threads: _Threads(calls: calls, followFailures: 1),
      )(session: session, teamId: 'team', reference: reference);

      expect(result.status, PostponedThreadReactivationStatus.followFailed);
      expect(calls, <String>['isFollowing', 'follow']);
      expect(postponed.removed, isEmpty);
    },
  );

  test(
    'remove failure is recoverable and retry skips a confirmed follow',
    () async {
      final List<String> calls = <String>[];
      final _Threads threads = _Threads(calls: calls);
      final _Postponed postponed = _Postponed(calls: calls, removeFailures: 1);
      final ReactivatePostponedThread workflow = _workflow(
        postponed: postponed,
        threads: threads,
      );

      final PostponedThreadReactivationResult first = await workflow(
        session: session,
        teamId: 'team',
        reference: reference,
      );
      final PostponedThreadReactivationResult retry = await workflow(
        session: session,
        teamId: 'team',
        reference: reference,
      );

      expect(first.status, PostponedThreadReactivationStatus.removeFailed);
      expect(retry.status, PostponedThreadReactivationStatus.reactivated);
      expect(calls, <String>[
        'isFollowing',
        'follow',
        'remove',
        'isFollowing',
        'remove',
      ]);
    },
  );
}

ReactivatePostponedThread _workflow({
  InboxSettingsSnapshot? settings,
  required _Postponed postponed,
  required _Threads threads,
}) => ReactivatePostponedThread(
  settings: _Settings(settings ?? _settings()),
  postponed: postponed,
  threads: threads,
);

InboxSettingsSnapshot _settings({bool reactivateOnMention = true}) =>
    InboxSettingsSnapshot(
      state: InboxSettingsLoadState.parsed,
      settings: InboxSettings(
        postponed: InboxPostponedSettings(
          reactivateOnMention: reactivateOnMention,
        ),
      ),
    );

final class _Settings extends InboxSettingsRepository {
  const _Settings(this.snapshot);

  final InboxSettingsSnapshot snapshot;

  @override
  Future<InboxSettingsSnapshot> load({required AuthSession session}) async =>
      snapshot;

  @override
  Future<void> save({
    required AuthSession session,
    required InboxSettings settings,
  }) async {}
}

final class _Postponed extends PostponedRepository {
  _Postponed({required this.calls, this.removeFailures = 0});

  final List<String> calls;
  int removeFailures;
  final List<PostponedReference> removed = <PostponedReference>[];

  @override
  Future<PostponedReferencesSnapshot> load({
    required AuthSession session,
  }) async => PostponedReferencesSnapshot(const <PostponedReference>[]);

  @override
  Future<void> remove({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {
    calls.add('remove');
    if (removeFailures-- > 0) throw StateError('remove failed');
    removed.addAll(references);
  }

  @override
  Future<void> save({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {}
}

final class _Threads extends ThreadRepository {
  _Threads({
    required this.calls,
    this.following = false,
    this.followFailures = 0,
  });

  final List<String> calls;
  bool following;
  int followFailures;

  @override
  Future<bool> isFollowing({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
  }) async {
    calls.add('isFollowing');
    return following;
  }

  @override
  Future<void> follow({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
  }) async {
    calls.add('follow');
    if (followFailures-- > 0) throw StateError('follow failed');
    following = true;
  }
}
