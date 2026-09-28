import 'package:mattermost_flutter/src/features/inbox/domain/models/canonical_inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_settings.dart';

/// Builds presentation items, combining compatible direct messages by sender.
///
/// [InboxDirectGroupingMode.consecutive] bundles only consecutive direct
/// messages from the same author in the same dialog. Its bounded [window] is
/// applied between adjacent messages, so a transitive run remains one bundle
/// while every individual gap stays within the limit. `none` keeps every
/// message separate; `conversation` joins compatible messages from the whole
/// source snapshot, regardless of the gap.
///
/// A channel remains part of the identity because one sender can participate
/// in more than one group-message conversation. Automation messages also stay
/// separate so they keep their dedicated Inbox section.
const Duration defaultDirectMessageGroupingWindow = Duration(minutes: 2);

List<InboxItem> groupDirectMessages(
  Iterable<CanonicalInboxCandidate> candidates, {
  InboxDirectGroupingSettings directGrouping =
      const InboxDirectGroupingSettings(),
  Duration? window,
}) {
  final Duration effectiveWindow =
      window ?? Duration(seconds: directGrouping.windowSeconds);
  if (effectiveWindow.isNegative) {
    throw ArgumentError.value(
      effectiveWindow,
      'window',
      'must not be negative',
    );
  }
  final List<CanonicalInboxCandidate> ordered = candidates.toList()
    ..sort(_compareByActivity);
  final List<InboxItem> result = <InboxItem>[];
  final List<List<InboxPostCandidate>> directMessageBundles =
      <List<InboxPostCandidate>>[];
  final Map<
    ({String channelId, String authorId, InboxAutomationClass automationClass}),
    List<InboxPostCandidate>
  >
  conversationBundles =
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
        switch (directGrouping.mode) {
          case InboxDirectGroupingMode.none:
            directMessageBundles.add(<InboxPostCandidate>[candidate]);
          case InboxDirectGroupingMode.consecutive:
            if (directMessageBundles.isNotEmpty &&
                _canAppendToDirectBundle(
                  directMessageBundles.last,
                  candidate,
                  effectiveWindow,
                )) {
              directMessageBundles.last.add(candidate);
            } else {
              directMessageBundles.add(<InboxPostCandidate>[candidate]);
            }
          case InboxDirectGroupingMode.conversation:
            final key = (
              channelId: candidate.post.channelId,
              authorId: candidate.post.author.id,
              automationClass: candidate.automationClass,
            );
            conversationBundles
                .putIfAbsent(key, () => <InboxPostCandidate>[])
                .add(candidate);
        }
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
  directMessageBundles.addAll(conversationBundles.values);
  for (final List<InboxPostCandidate> messages in directMessageBundles) {
    final InboxPostCandidate first = messages.first;
    result.add(
      DirectMessageBundleInboxItem(
        channelId: first.post.channelId,
        authorId: first.post.author.id,
        automationClass: first.automationClass,
        messages: messages,
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

bool _canAppendToDirectBundle(
  List<InboxPostCandidate> bundle,
  InboxPostCandidate candidate,
  Duration window,
) {
  final InboxPostCandidate previous = bundle.last;
  return previous.post.channelId == candidate.post.channelId &&
      previous.post.author.id == candidate.post.author.id &&
      previous.automationClass == candidate.automationClass &&
      candidate.post.sentAt.difference(previous.post.sentAt) <= window;
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
