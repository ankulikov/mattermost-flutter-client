import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/canonicalize_inbox_candidates.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/group_direct_messages.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/reconcile_queues.dart';

/// Applies one typed root-post delta to an Inbox snapshot.
///
/// Creates use the normal canonicalization/grouping pipeline. Edits only swap
/// the preview of an already-present item and deletes only remove known roots;
/// neither operation may recalculate membership from a changed post body.
InboxSnapshot applyInboxPostChange({
  required InboxSnapshot snapshot,
  required String postId,
  required InboxPostCandidate? candidate,
  InboxPostChangeKind? kind,
}) {
  final InboxPostChangeKind changeKind =
      kind ??
      (candidate == null
          ? InboxPostChangeKind.deleted
          : InboxPostChangeKind.created);
  return switch (changeKind) {
    InboxPostChangeKind.created => candidate == null
        ? snapshot
        : _applyCreated(snapshot: snapshot, postId: postId, candidate: candidate),
    InboxPostChangeKind.edited => candidate == null
        ? snapshot
        : _applyEdited(snapshot: snapshot, postId: postId, candidate: candidate),
    InboxPostChangeKind.deleted => _applyDeleted(snapshot: snapshot, postId: postId),
  };
}

InboxSnapshot _applyCreated({
  required InboxSnapshot snapshot,
  required String postId,
  required InboxPostCandidate candidate,
}) {
  final List<InboxThreadCandidate> threads = <InboxThreadCandidate>[];
  final List<InboxPostCandidate> posts = <InboxPostCandidate>[];

  for (final InboxItem item in snapshot.newItems) {
    switch (item) {
      case ThreadInboxItem():
        threads.add(_threadCandidate(item));
      case ChannelPostInboxItem():
        if (item.post.id != postId) posts.add(item.candidate);
      case DirectMessageBundleInboxItem():
        posts.addAll(
          item.messages.where(
            (InboxPostCandidate message) => message.post.id != postId,
          ),
        );
      case UnavailablePostponedInboxItem():
        break;
    }
  }
  if (!candidate.post.isReply) posts.add(candidate);

  return _preservingMetadata(
    snapshot,
    reconcileQueues(
    newItems: groupDirectMessages(
      canonicalizeInboxCandidates(
        InboxSourceSnapshot(threads: threads, posts: posts),
      ),
    ),
    postponedItems: snapshot.postponedItems,
    builtAt: snapshot.builtAt,
    hasIncompleteMentionReconstruction:
        snapshot.hasIncompleteMentionReconstruction,
    ),
  );
}

InboxSnapshot _applyEdited({
  required InboxSnapshot snapshot,
  required String postId,
  required InboxPostCandidate candidate,
}) => InboxSnapshot(
  newItems: snapshot.newItems
      .map((InboxItem item) => _editItem(item, postId, candidate))
      .toList(growable: false),
  postponedItems: snapshot.postponedItems
      .map((InboxItem item) => _editItem(item, postId, candidate))
      .toList(growable: false),
  builtAt: snapshot.builtAt,
  completeness: snapshot.completeness,
  diagnosticsCodes: snapshot.diagnosticsCodes,
  sourceFailures: snapshot.sourceFailures,
);

InboxItem _editItem(
  InboxItem item,
  String postId,
  InboxPostCandidate preview,
) => switch (item) {
  ChannelPostInboxItem(:final candidate)
      when candidate.post.id == postId =>
    ChannelPostInboxItem(
      candidate: candidate.withPost(preview.post),
      postponedAt: item.postponedAt,
    ),
  DirectMessageBundleInboxItem(:final messages)
      when messages.any((InboxPostCandidate message) => message.post.id == postId) =>
    DirectMessageBundleInboxItem(
      channelId: item.channelId,
      authorId: item.authorId,
      automationClass: item.automationClass,
      messages: messages
          .map(
            (InboxPostCandidate message) => message.post.id == postId
                ? message.withPost(preview.post)
                : message,
          )
          .toList(growable: false),
      postponedAt: item.postponedAt,
    ),
  ThreadInboxItem(:final thread)
      when thread.id == postId =>
    ThreadInboxItem(
      thread: FollowedThread(
        root: preview.post.withThreadSummary(
          replyCount: thread.replyCount,
          lastReplyAt: thread.lastReplyAt,
        ),
        replyCount: thread.replyCount,
        lastReplyAt: thread.lastReplyAt,
        lastViewedAt: thread.lastViewedAt,
        unreadReplies: thread.unreadReplies,
        unreadMentions: thread.unreadMentions,
        participants: thread.participants,
      ),
      channel: item.channel,
      teamId: item.teamId,
      rootAttentionReason: item.rootAttentionReason,
      reactivatesPostponed: item.reactivatesPostponed,
      postponedAt: item.postponedAt,
    ),
  _ => item,
};

InboxSnapshot _applyDeleted({
  required InboxSnapshot snapshot,
  required String postId,
}) => InboxSnapshot(
  newItems: _removePost(snapshot.newItems, postId),
  // A postponed reference is durable, user-owned state. It is preserved here;
  // a later hydration may render it as the content-free unavailable placeholder.
  postponedItems: snapshot.postponedItems,
  builtAt: snapshot.builtAt,
  completeness: snapshot.completeness,
  diagnosticsCodes: snapshot.diagnosticsCodes,
  sourceFailures: snapshot.sourceFailures,
);

List<InboxItem> _removePost(Iterable<InboxItem> items, String postId) => items
    .map<InboxItem?>((InboxItem item) => switch (item) {
          DirectMessageBundleInboxItem(:final messages)
              when messages.any(
                (InboxPostCandidate candidate) => candidate.post.id == postId,
              ) =>
            messages.length == 1
                ? null
                : DirectMessageBundleInboxItem(
                    channelId: item.channelId,
                    authorId: item.authorId,
                    automationClass: item.automationClass,
                    messages: messages
                        .where(
                          (InboxPostCandidate candidate) =>
                              candidate.post.id != postId,
                        )
                        .toList(growable: false),
                    postponedAt: item.postponedAt,
                  ),
          ChannelPostInboxItem(:final post) when post.id == postId => null,
          ThreadInboxItem(:final thread) when thread.id == postId => null,
          _ => item,
        })
    .whereType<InboxItem>()
    .toList(growable: false);

InboxSnapshot _preservingMetadata(InboxSnapshot previous, InboxSnapshot next) =>
    InboxSnapshot(
      newItems: next.newItems,
      postponedItems: next.postponedItems,
      builtAt: next.builtAt,
      completeness: previous.completeness,
      diagnosticsCodes: previous.diagnosticsCodes,
      sourceFailures: previous.sourceFailures,
    );

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
