import 'package:mattermost_flutter/src/features/inbox/domain/models/canonical_inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';

const Duration directMessageBundleGap = Duration(minutes: 2);

/// Builds presentation items, combining adjacent compatible direct messages.
///
/// The two-minute boundary is inclusive and grouping is intentionally
/// transitive: every adjacent pair controls whether a bundle continues.
List<InboxItem> groupDirectMessages(
  Iterable<CanonicalInboxCandidate> candidates,
) {
  final List<CanonicalInboxCandidate> ordered = candidates.toList()
    ..sort(_compareByActivity);
  final List<InboxItem> result = <InboxItem>[];
  final List<InboxPostCandidate> directCandidates = <InboxPostCandidate>[];
  final List<InboxPostCandidate> directBundle = <InboxPostCandidate>[];

  void flushBundle() {
    if (directBundle.isEmpty) return;
    final InboxPostCandidate first = directBundle.first;
    result.add(
      DirectMessageBundleInboxItem(
        channelId: first.post.channelId,
        authorId: first.post.author.id,
        automationClass: first.automationClass,
        messages: directBundle,
      ),
    );
    directBundle.clear();
  }

  for (final CanonicalInboxCandidate candidate in ordered) {
    switch (candidate) {
      case CanonicalDirectPostCandidate(:final InboxPostCandidate candidate):
        directCandidates.add(candidate);
      case CanonicalThreadCandidate(:final candidate):
        result.add(
          ThreadInboxItem(
            thread: candidate.thread,
            channel: candidate.channel,
            teamId: candidate.teamId,
            rootAttentionReason: candidate.rootAttentionReason,
            reactivatesPostponed: candidate.hasNewExplicitMention,
          ),
        );
      case CanonicalChannelPostCandidate(:final candidate):
        result.add(ChannelPostInboxItem(candidate: candidate));
    }
  }
  for (final InboxPostCandidate candidate in directCandidates) {
    if (directBundle.isEmpty || _canAppend(directBundle.last, candidate)) {
      directBundle.add(candidate);
    } else {
      flushBundle();
      directBundle.add(candidate);
    }
  }
  flushBundle();
  result.sort((InboxItem first, InboxItem second) {
    final int byActivity = first.lastActivityAt.compareTo(
      second.lastActivityAt,
    );
    return byActivity != 0 ? byActivity : first.key.compareTo(second.key);
  });
  return List<InboxItem>.unmodifiable(result);
}

bool _canAppend(InboxPostCandidate previous, InboxPostCandidate next) {
  if (previous.post.channelId != next.post.channelId ||
      previous.post.author.id != next.post.author.id ||
      previous.automationClass != next.automationClass) {
    return false;
  }
  final Duration gap = next.post.sentAt.difference(previous.post.sentAt);
  return gap >= Duration.zero && gap <= directMessageBundleGap;
}

int _compareByActivity(
  CanonicalInboxCandidate first,
  CanonicalInboxCandidate second,
) {
  final DateTime firstAt = _activity(first);
  final DateTime secondAt = _activity(second);
  final int byTime = firstAt.compareTo(secondAt);
  return byTime != 0 ? byTime : first.canonicalId.compareTo(second.canonicalId);
}

DateTime _activity(CanonicalInboxCandidate candidate) => switch (candidate) {
  CanonicalThreadCandidate(:final candidate) => candidate.thread.lastReplyAt,
  CanonicalDirectPostCandidate(:final candidate) => candidate.post.sentAt,
  CanonicalChannelPostCandidate(:final candidate) => candidate.post.sentAt,
};
