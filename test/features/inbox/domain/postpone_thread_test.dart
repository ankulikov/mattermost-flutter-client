import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/use_cases/postpone_thread.dart';

void main() {
  final AuthSession session = AuthSession(
    serverUrl: Uri.parse('https://chat.example.test'),
    userId: 'me',
    username: 'me',
  );
  final DateTime addedAt = DateTime.utc(2026, 9, 26, 10);

  test(
    'saves a durable thread reference before marking read and unfollowing',
    () async {
      final List<String> calls = <String>[];
      final _Postponed postponed = _Postponed(calls: calls);
      final _Threads threads = _Threads(calls: calls);

      final PendingPostponeThreadSideEffects result = await PostponeThread(
        postponed: postponed,
        threads: threads,
      )(session: session, item: _item(), addedAt: addedAt);

      expect(calls, <String>['save', 'markRead', 'unfollow']);
      expect(result.isComplete, isTrue);
      expect(postponed.saved, hasLength(1));
      expect(postponed.saved.single.kind, PostponedReferenceKind.thread);
      expect(postponed.saved.single.postId, 'root');
      expect(postponed.saved.single.targetPostId, 'root');
      expect(postponed.saved.single.addedAt, addedAt);
      expect(threads.readTimestamp, _item().thread.lastReplyAt);
    },
  );

  test(
    'does not run side effects when saving the durable reference fails',
    () async {
      final List<String> calls = <String>[];
      final _Postponed postponed = _Postponed(calls: calls, saveFailures: 1);
      final _Threads threads = _Threads(calls: calls);

      await expectLater(
        PostponeThread(postponed: postponed, threads: threads)(
          session: session,
          item: _item(),
          addedAt: addedAt,
        ),
        throwsStateError,
      );

      expect(calls, <String>['save']);
    },
  );

  test(
    'mark-read failure preserves the durable reference and retries in order',
    () async {
      final List<String> calls = <String>[];
      final _Postponed postponed = _Postponed(calls: calls);
      final _Threads threads = _Threads(calls: calls, markReadFailures: 1);
      final PostponeThread workflow = PostponeThread(
        postponed: postponed,
        threads: threads,
      );

      final PendingPostponeThreadSideEffects first = await workflow(
        session: session,
        item: _item(),
        addedAt: addedAt,
      );
      expect(first.pending, <PostponeThreadSideEffect>{
        PostponeThreadSideEffect.markRead,
        PostponeThreadSideEffect.unfollow,
      });
      expect(calls, <String>['save', 'markRead']);

      final PendingPostponeThreadSideEffects retried = await workflow.retry(
        session: session,
        pending: first,
      );
      expect(retried.isComplete, isTrue);
      expect(calls, <String>['save', 'markRead', 'markRead', 'unfollow']);
      expect(postponed.saved, hasLength(1));
    },
  );

  test(
    'unfollow failure retries only unfollow without another save or read',
    () async {
      final List<String> calls = <String>[];
      final _Postponed postponed = _Postponed(calls: calls);
      final _Threads threads = _Threads(calls: calls, unfollowFailures: 1);
      final PostponeThread workflow = PostponeThread(
        postponed: postponed,
        threads: threads,
      );

      final PendingPostponeThreadSideEffects first = await workflow(
        session: session,
        item: _item(),
        addedAt: addedAt,
      );
      expect(first.pending, <PostponeThreadSideEffect>{
        PostponeThreadSideEffect.unfollow,
      });
      expect(calls, <String>['save', 'markRead', 'unfollow']);

      final PendingPostponeThreadSideEffects retried = await workflow.retry(
        session: session,
        pending: first,
      );
      expect(retried.isComplete, isTrue);
      expect(calls, <String>['save', 'markRead', 'unfollow', 'unfollow']);
      expect(postponed.saved, hasLength(1));
    },
  );
}

ThreadInboxItem _item() => ThreadInboxItem(
  teamId: 'team',
  channel: const SidebarChannel(
    id: 'channel',
    teamId: 'team',
    name: 'channel',
    displayName: 'Channel',
    kind: ChannelKind.publicChannel,
  ),
  thread: FollowedThread(
    root: Post(
      id: 'root',
      channelId: 'channel',
      author: const PostAuthor(id: 'other', displayName: 'Other'),
      sentAt: DateTime.utc(2026, 9, 26, 9),
      message: 'Private message fixture',
    ),
    replyCount: 1,
    lastReplyAt: DateTime.utc(2026, 9, 26, 9, 30),
    lastViewedAt: DateTime.utc(2026, 9, 26, 8),
    unreadReplies: 1,
    unreadMentions: 0,
  ),
);

final class _Postponed extends PostponedRepository {
  _Postponed({required this.calls, this.saveFailures = 0});

  final List<String> calls;
  int saveFailures;
  final List<PostponedReference> saved = <PostponedReference>[];

  @override
  Future<PostponedReferencesSnapshot> load({
    required AuthSession session,
  }) async => PostponedReferencesSnapshot(const <PostponedReference>[]);

  @override
  Future<void> remove({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {}

  @override
  Future<void> save({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {
    calls.add('save');
    if (saveFailures-- > 0) throw StateError('save failed');
    saved.addAll(references);
  }
}

final class _Threads extends ThreadRepository {
  _Threads({
    required this.calls,
    this.markReadFailures = 0,
    this.unfollowFailures = 0,
  });

  final List<String> calls;
  int markReadFailures;
  int unfollowFailures;
  DateTime? readTimestamp;

  @override
  Future<void> markRead({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
    required DateTime timestamp,
  }) async {
    calls.add('markRead');
    readTimestamp = timestamp;
    if (markReadFailures-- > 0) throw StateError('read failed');
  }

  @override
  Future<void> unfollow({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
  }) async {
    calls.add('unfollow');
    if (unfollowFailures-- > 0) throw StateError('unfollow failed');
  }
}
