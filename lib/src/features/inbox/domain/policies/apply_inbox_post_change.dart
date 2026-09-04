import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/canonicalize_inbox_candidates.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/group_direct_messages.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/reconcile_queues.dart';

/// Applies one realtime root-post change through the same canonicalization,
/// direct-message grouping and queue reconciliation used by REST snapshots.
InboxSnapshot applyInboxPostChange({
  required InboxSnapshot snapshot,
  required String postId,
  required InboxPostCandidate? candidate,
}) {
  final List<InboxThreadCandidate> threads = <InboxThreadCandidate>[];
  final List<InboxPostCandidate> posts = <InboxPostCandidate>[];

  for (final InboxItem item in snapshot.newItems) {
    switch (item) {
      case ThreadInboxItem():
        if (item.thread.id != postId) {
          threads.add(_threadCandidate(item));
        } else if (candidate != null) {
          threads.add(_threadCandidate(item, root: candidate.post));
        }
      case ChannelPostInboxItem():
        if (item.post.id != postId) posts.add(item.candidate);
      case DirectMessageBundleInboxItem():
        posts.addAll(
          item.messages.where(
            (InboxPostCandidate message) => message.post.id != postId,
          ),
        );
    }
  }
  if (candidate != null && !candidate.post.isReply) posts.add(candidate);

  return reconcileQueues(
    newItems: groupDirectMessages(
      canonicalizeInboxCandidates(
        InboxSourceSnapshot(threads: threads, posts: posts),
      ),
    ),
    postponedItems: snapshot.postponedItems,
    builtAt: snapshot.builtAt,
    hasIncompleteMentionReconstruction:
        snapshot.hasIncompleteMentionReconstruction,
  );
}

InboxThreadCandidate _threadCandidate(
  ThreadInboxItem item, {
  ChannelPost? root,
}) => InboxThreadCandidate(
  thread: root == null
      ? item.thread
      : FollowedThread(
          root: root.withThreadSummary(
            replyCount: item.thread.replyCount,
            lastReplyAt: item.thread.lastReplyAt,
          ),
          replyCount: item.thread.replyCount,
          lastReplyAt: item.thread.lastReplyAt,
          lastViewedAt: item.thread.lastViewedAt,
          unreadReplies: item.thread.unreadReplies,
          unreadMentions: item.thread.unreadMentions,
          participants: item.thread.participants,
        ),
  channel: item.channel,
  teamId: item.teamId,
  rootAttentionReason: item.rootAttentionReason,
  hasNewExplicitMention: item.reactivatesPostponed,
);
