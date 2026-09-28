import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';

enum InboxSection {
  mentions,
  groupMentions,
  botsAndIntegrations,
  directMessages,
  threads,
}

/// Assigns one Inbox item to its single presentation section.
///
/// An explicit mention in a reply makes a followed thread a Threads item. A
/// thread root otherwise keeps its original source: direct roots stay in DMs
/// and mentioned channel roots stay in Mentions.
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
        : reason == InboxAttentionReason.groupMention
        ? InboxSection.groupMentions
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
  ChannelPostInboxItem(
    candidate: InboxPostCandidate(reason: InboxAttentionReason.groupMention),
  ) =>
    InboxSection.groupMentions,
  ChannelPostInboxItem() => InboxSection.mentions,
};

bool _isMention(InboxAttentionReason? reason) => switch (reason) {
  InboxAttentionReason.directMention ||
  InboxAttentionReason.keywordMention ||
  InboxAttentionReason.channelMention => true,
  InboxAttentionReason.groupMention ||
  InboxAttentionReason.allMessagesSubscription ||
  null => false,
};
