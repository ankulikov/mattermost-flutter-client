import 'package:mattermost_flutter/src/features/inbox/domain/models/canonical_inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';

/// Builds presentation items, combining compatible direct messages by sender.
///
/// A channel remains part of the identity because one sender can participate
/// in more than one group-message conversation. Automation messages also stay
/// separate so human and automated messages never share one presentation item.
List<InboxItem> groupDirectMessages(
  Iterable<CanonicalInboxCandidate> candidates,
) {
  final List<CanonicalInboxCandidate> ordered = candidates.toList()
    ..sort(_compareByActivity);
  final List<InboxItem> result = <InboxItem>[];
  final Map<
    ({String channelId, String authorId, InboxAutomationClass automationClass}),
    List<InboxPostCandidate>
  >
  directMessages =
      <
        ({
          String channelId,
          String authorId,
          InboxAutomationClass automationClass,
        }),
        List<InboxPostCandidate>
      >{};

  for (final CanonicalInboxCandidate candidate in ordered) {
    switch (candidate) {
      case CanonicalDirectPostCandidate(:final InboxPostCandidate candidate):
        final key = (
          channelId: candidate.post.channelId,
          authorId: candidate.post.author.id,
          automationClass: candidate.automationClass,
        );
        directMessages
            .putIfAbsent(key, () => <InboxPostCandidate>[])
            .add(candidate);
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
  for (final MapEntry(:key, :value) in directMessages.entries) {
    result.add(
      DirectMessageBundleInboxItem(
        channelId: key.channelId,
        authorId: key.authorId,
        automationClass: key.automationClass,
        messages: value,
      ),
    );
  }
  result.sort((InboxItem first, InboxItem second) {
    final int byActivity = first.lastActivityAt.compareTo(
      second.lastActivityAt,
    );
    return byActivity != 0 ? byActivity : first.key.compareTo(second.key);
  });
  return List<InboxItem>.unmodifiable(result);
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
