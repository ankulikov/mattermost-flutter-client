import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_settings.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_settings_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';

/// The recoverable outcome of one explicit-mention reactivation attempt.
///
/// It deliberately carries no transport error or post content. The durable
/// Postponed preference stays authoritative until [reactivated] is returned.
enum PostponedThreadReactivationStatus {
  reactivated,
  settingsUnavailable,
  disabledBySettings,
  followFailed,
  removeFailed,
}

final class PostponedThreadReactivationResult {
  const PostponedThreadReactivationResult(this.status);

  final PostponedThreadReactivationStatus status;

  bool get didReactivate =>
      status == PostponedThreadReactivationStatus.reactivated;
}

/// Reactivates exactly one postponed CRT thread after an explicit mention.
///
/// The sequence is intentionally durable: follow first when necessary, then
/// remove the exact Postponed preference, and only then allow the caller to
/// place the thread in New. Repeating the workflow re-checks follow state and
/// only repeats idempotent server operations that have not been confirmed.
final class ReactivatePostponedThread {
  const ReactivatePostponedThread({
    required InboxSettingsRepository settings,
    required PostponedRepository postponed,
    required ThreadRepository threads,
  }) : _settings = settings,
       _postponed = postponed,
       _threads = threads;

  final InboxSettingsRepository _settings;
  final PostponedRepository _postponed;
  final ThreadRepository _threads;

  Future<PostponedThreadReactivationResult> call({
    required AuthSession session,
    required String teamId,
    required PostponedReference reference,
  }) async {
    final InboxSettingsSnapshot settings;
    try {
      settings = await _settings.load(session: session);
    } on Object {
      return const PostponedThreadReactivationResult(
        PostponedThreadReactivationStatus.settingsUnavailable,
      );
    }

    // A missing/malformed setting must not turn a durable user choice into a
    // New item. Only an explicit, parsed server setting authorizes this.
    if (settings.state != InboxSettingsLoadState.parsed ||
        !settings.settings.enabled ||
        !settings.settings.postponed.reactivateOnMention) {
      return const PostponedThreadReactivationResult(
        PostponedThreadReactivationStatus.disabledBySettings,
      );
    }

    try {
      final bool following = await _threads.isFollowing(
        session: session,
        teamId: teamId,
        rootPostId: reference.postId,
      );
      if (!following) {
        await _threads.follow(
          session: session,
          teamId: teamId,
          rootPostId: reference.postId,
        );
      }
    } on Object {
      return const PostponedThreadReactivationResult(
        PostponedThreadReactivationStatus.followFailed,
      );
    }

    try {
      final PostponedBatchOutcome outcome = await _postponed.removeWithOutcome(
        session: session,
        references: <PostponedReference>[reference],
      );
      if (outcome.requiresReconciliation) {
        return const PostponedThreadReactivationResult(
          PostponedThreadReactivationStatus.removeFailed,
        );
      }
    } on Object {
      return const PostponedThreadReactivationResult(
        PostponedThreadReactivationStatus.removeFailed,
      );
    }
    return const PostponedThreadReactivationResult(
      PostponedThreadReactivationStatus.reactivated,
    );
  }
}
