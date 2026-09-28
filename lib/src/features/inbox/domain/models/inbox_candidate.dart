import 'dart:collection';

import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';

/// The server- or client-derived reason why a root post needs attention.
enum InboxAttentionReason {
  directMention,
  keywordMention,
  groupMention,
  channelMention,
  allMessagesSubscription,
}

/// Whether a direct message was sent by a person or an automation.
enum InboxAutomationClass { person, automation }

/// A post projection with Inbox-only eligibility metadata.
///
/// Transport mappers decide [reason] from server mention data or the notification
/// policy. This model deliberately does not expose wire DTOs to the domain.
final class InboxPostCandidate {
  InboxPostCandidate({
    required this.post,
    required this.channel,
    required this.reason,
    this.isIncoming = true,
    this.isSystem = false,
    this.isSilentNotification = false,
    this.isFromBot = false,
    this.isFromWebhook = false,
    this.isFromPlugin = false,
  });

  final Post post;
  final SidebarChannel channel;
  final InboxAttentionReason reason;
  final bool isIncoming;
  final bool isSystem;
  final bool isSilentNotification;
  final bool isFromBot;
  final bool isFromWebhook;
  final bool isFromPlugin;

  bool get isEligible =>
      isIncoming &&
      !isSystem &&
      !isSilentNotification &&
      !post.isDeleted &&
      !post.isReply;

  InboxAutomationClass get automationClass =>
      isFromBot || isFromWebhook || isFromPlugin
      ? InboxAutomationClass.automation
      : InboxAutomationClass.person;

  bool get isDirect => channel.isDialog;

  /// Replaces displayable post content while retaining the original Inbox
  /// membership decision. This is used for `post_edited`: an edit must not
  /// change the historic attention reason, channel identity, or automation
  /// classification that admitted the item to Inbox.
  InboxPostCandidate withPost(Post value) => InboxPostCandidate(
    post: value,
    channel: channel,
    reason: reason,
    isIncoming: isIncoming,
    isSystem: isSystem,
    isSilentNotification: isSilentNotification,
    isFromBot: isFromBot,
    isFromWebhook: isFromWebhook,
    isFromPlugin: isFromPlugin,
  );
}

/// A followed CRT thread included in the Inbox source snapshot.
final class InboxThreadCandidate {
  InboxThreadCandidate({
    required this.thread,
    required this.channel,
    required this.teamId,
    this.rootAttentionReason,
    this.hasNewExplicitMention = false,
  });

  final FollowedThread thread;
  final SidebarChannel channel;
  final String teamId;

  /// The attention reason of the root post, when it can be reconstructed.
  ///
  /// This survives canonicalization so a thread whose root introduced an
  /// Inbox mention can remain in Mentions until a later reply needs attention.
  final InboxAttentionReason? rootAttentionReason;

  /// True only when the incoming thread update is an explicit mention. It lets
  /// that mention reactivate an otherwise postponed thread.
  final bool hasNewExplicitMention;

  bool get isEligible => thread.unreadReplies > 0 || thread.unreadMentions > 0;
}

/// The raw, network-first inputs needed to construct an Inbox snapshot.
final class InboxSourceSnapshot {
  InboxSourceSnapshot({
    Iterable<InboxThreadCandidate> threads = const <InboxThreadCandidate>[],
    Iterable<InboxPostCandidate> posts = const <InboxPostCandidate>[],
    this.builtAt,
  }) : threads = UnmodifiableListView<InboxThreadCandidate>(threads.toList()),
       posts = UnmodifiableListView<InboxPostCandidate>(posts.toList());

  final List<InboxThreadCandidate> threads;
  final List<InboxPostCandidate> posts;
  final DateTime? builtAt;
}
