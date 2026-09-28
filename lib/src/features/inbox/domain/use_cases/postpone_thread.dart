import 'dart:collection';

import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';

/// Side effects that follow a durable postponed-thread preference.
///
/// They are intentionally named without carrying a server error or message
/// content: callers can expose retry state without leaking response details.
enum PostponeThreadSideEffect { markRead, unfollow }

/// A durable thread reference with the side effects that still need retrying.
final class PendingPostponeThreadSideEffects {
  PendingPostponeThreadSideEffects({
    required this.reference,
    required this.teamId,
    required this.readTimestamp,
    required Iterable<PostponeThreadSideEffect> pending,
  }) : pending = UnmodifiableSetView<PostponeThreadSideEffect>(
         Set<PostponeThreadSideEffect>.of(pending),
       );

  final PostponedReference reference;
  final String teamId;
  final DateTime readTimestamp;
  final Set<PostponeThreadSideEffect> pending;

  bool get isComplete => pending.isEmpty;
}

/// Saves a CRT thread to Postponed before changing its server read/follow state.
///
/// A failed preference save is deliberately propagated, so callers must not
/// move the item locally. Once it succeeds, retrying only runs the remaining
/// side effects and never writes the same preference a second time.
final class PostponeThread {
  const PostponeThread({
    required PostponedRepository postponed,
    required ThreadRepository threads,
  }) : _postponed = postponed,
       _threads = threads;

  final PostponedRepository _postponed;
  final ThreadRepository _threads;

  Future<PendingPostponeThreadSideEffects> call({
    required AuthSession session,
    required ThreadInboxItem item,
    required DateTime addedAt,
  }) async {
    final PostponedReference reference = PostponedReference(
      postId: item.thread.id,
      kind: PostponedReferenceKind.thread,
      addedAt: addedAt,
      targetPostId: item.thread.root.id,
    );
    final PostponedBatchOutcome outcome = await _postponed.saveWithOutcome(
      session: session,
      references: <PostponedReference>[reference],
    );
    if (outcome.requiresReconciliation) {
      throw const PostponedBatchReconciliationRequired();
    }
    return retry(
      session: session,
      pending: PendingPostponeThreadSideEffects(
        reference: reference,
        teamId: item.teamId,
        readTimestamp: item.thread.lastReplyAt,
        pending: PostponeThreadSideEffect.values,
      ),
    );
  }

  /// Retries only unfinished work after a preference has become durable.
  Future<PendingPostponeThreadSideEffects> retry({
    required AuthSession session,
    required PendingPostponeThreadSideEffects pending,
  }) async {
    final Set<PostponeThreadSideEffect> remaining =
        Set<PostponeThreadSideEffect>.of(pending.pending);
    final String rootPostId = pending.reference.postId;

    if (remaining.contains(PostponeThreadSideEffect.markRead)) {
      try {
        await _threads.markRead(
          session: session,
          teamId: pending.teamId,
          rootPostId: rootPostId,
          timestamp: pending.readTimestamp,
        );
        remaining.remove(PostponeThreadSideEffect.markRead);
      } on Object {
        return PendingPostponeThreadSideEffects(
          reference: pending.reference,
          teamId: pending.teamId,
          readTimestamp: pending.readTimestamp,
          pending: remaining,
        );
      }
    }

    if (remaining.contains(PostponeThreadSideEffect.unfollow)) {
      try {
        await _threads.unfollow(
          session: session,
          teamId: pending.teamId,
          rootPostId: rootPostId,
        );
        remaining.remove(PostponeThreadSideEffect.unfollow);
      } on Object {
        // The preference and any successfully applied prior side effect remain
        // authoritative; the returned typed state is safe to retry.
      }
    }
    return PendingPostponeThreadSideEffects(
      reference: pending.reference,
      teamId: pending.teamId,
      readTimestamp: pending.readTimestamp,
      pending: remaining,
    );
  }
}
