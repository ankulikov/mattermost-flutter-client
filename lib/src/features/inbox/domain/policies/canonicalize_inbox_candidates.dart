import 'package:mattermost_flutter/src/features/inbox/domain/models/canonical_inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';

/// Converts independent Inbox sources into one idempotent canonical stream.
///
/// A followed thread wins over every post that belongs to it. Posts are then
/// deduplicated by Mattermost post id before direct conversations are grouped.
List<CanonicalInboxCandidate> canonicalizeInboxCandidates(
  InboxSourceSnapshot sources,
) {
  final Map<String, InboxThreadCandidate> threadsByRoot =
      <String, InboxThreadCandidate>{};
  for (final InboxThreadCandidate candidate in sources.threads) {
    if (!candidate.isEligible) continue;
    final InboxThreadCandidate? current = threadsByRoot[candidate.thread.id];
    if (current == null ||
        (!current.hasNewExplicitMention && candidate.hasNewExplicitMention)) {
      threadsByRoot[candidate.thread.id] = candidate;
    }
  }

  final Map<String, InboxPostCandidate> postsById =
      <String, InboxPostCandidate>{};
  for (final InboxPostCandidate candidate in sources.posts) {
    if (!candidate.isEligible) continue;
    if (threadsByRoot.containsKey(candidate.post.rootId) ||
        threadsByRoot.containsKey(candidate.post.id)) {
      continue;
    }

    final InboxPostCandidate? current = postsById[candidate.post.id];
    if (current == null ||
        _postPrecedence(candidate) > _postPrecedence(current)) {
      postsById[candidate.post.id] = candidate;
    }
  }

  final List<CanonicalInboxCandidate> result = <CanonicalInboxCandidate>[
    ...threadsByRoot.values.map(CanonicalThreadCandidate.new),
    ...postsById.values.map(
      (InboxPostCandidate candidate) => candidate.isDirect
          ? CanonicalDirectPostCandidate(candidate)
          : CanonicalChannelPostCandidate(candidate),
    ),
  ];
  result.sort(_compareCanonicalCandidates);
  return List<CanonicalInboxCandidate>.unmodifiable(result);
}

int _postPrecedence(InboxPostCandidate candidate) {
  final int reason = switch (candidate.reason) {
    InboxAttentionReason.directMention => 5,
    InboxAttentionReason.keywordMention => 4,
    InboxAttentionReason.groupMention => 3,
    InboxAttentionReason.channelMention => 2,
    InboxAttentionReason.allMessagesSubscription => 1,
  };
  return reason + (candidate.isDirect ? 10 : 0);
}

int _compareCanonicalCandidates(
  CanonicalInboxCandidate first,
  CanonicalInboxCandidate second,
) {
  final DateTime firstAt = switch (first) {
    CanonicalThreadCandidate(:final candidate) => candidate.thread.lastReplyAt,
    CanonicalDirectPostCandidate(:final candidate) => candidate.post.sentAt,
    CanonicalChannelPostCandidate(:final candidate) => candidate.post.sentAt,
  };
  final DateTime secondAt = switch (second) {
    CanonicalThreadCandidate(:final candidate) => candidate.thread.lastReplyAt,
    CanonicalDirectPostCandidate(:final candidate) => candidate.post.sentAt,
    CanonicalChannelPostCandidate(:final candidate) => candidate.post.sentAt,
  };
  final int byTime = firstAt.compareTo(secondAt);
  return byTime != 0 ? byTime : first.canonicalId.compareTo(second.canonicalId);
}
