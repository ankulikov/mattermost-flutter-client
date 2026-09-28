import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';

enum InboxSection {
  mentions,
  allActivity,
  botsAndIntegrations,
  directMessages,
  threads,
}

/// Assigns one Inbox item to its single presentation section.
///
/// An explicit mention in a reply makes a followed thread a Threads item. A
/// thread root otherwise keeps its original source: direct roots stay in DMs
/// and mentioned channel roots stay in Mentions. Ordinary channel roots have
/// their own All activity section and must never be presented as mentions.
InboxSection classifyInboxSection(InboxItem item) => switch (item) {
  ThreadInboxItem(
    thread: final thread,
    channel: final channel,
    rootAttentionReason: final reason,
  ) =>
    thread.unreadMentions > 0
        ? InboxSection.threads
        : channel.isDialog
        ? InboxSection.directMessages
        : _isMention(reason)
        ? InboxSection.mentions
        : InboxSection.threads,
  DirectMessageBundleInboxItem(
    automationClass: InboxAutomationClass.automation,
  ) =>
    InboxSection.botsAndIntegrations,
  DirectMessageBundleInboxItem() => InboxSection.directMessages,
  ChannelPostInboxItem(
    candidate: InboxPostCandidate(
      automationClass: InboxAutomationClass.automation,
    ),
  ) =>
    InboxSection.botsAndIntegrations,
  ChannelPostInboxItem(candidate: InboxPostCandidate(reason: final reason)) =>
    _isMention(reason) ? InboxSection.mentions : InboxSection.allActivity,
  // A content-free postponed reference has no reliable attention reason. Use
  // the neutral section rather than incorrectly claiming it was a mention.
  UnavailablePostponedInboxItem() => InboxSection.allActivity,
};

bool _isMention(InboxAttentionReason? reason) => switch (reason) {
  InboxAttentionReason.directMention ||
  InboxAttentionReason.keywordMention ||
  InboxAttentionReason.groupMention ||
  InboxAttentionReason.channelMention => true,
  InboxAttentionReason.allMessagesSubscription || null => false,
};
