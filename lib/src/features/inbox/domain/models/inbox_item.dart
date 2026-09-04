import 'dart:collection';

import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';

enum InboxQueue { newItems, postponed }

sealed class InboxItem {
  const InboxItem({this.postponedAt});

  final DateTime? postponedAt;
  String get key;
  List<String> get postIds;
  Set<String> get threadRootIds;
  DateTime get lastActivityAt;
}

final class ThreadInboxItem extends InboxItem {
  const ThreadInboxItem({
    required this.thread,
    this.reactivatesPostponed = false,
    super.postponedAt,
  });

  final FollowedThread thread;
  final bool reactivatesPostponed;

  @override
  String get key => 'thread:${thread.id}';
  @override
  List<String> get postIds =>
      List<String>.unmodifiable(<String>[thread.root.id]);
  @override
  Set<String> get threadRootIds =>
      Set<String>.unmodifiable(<String>{thread.id});
  @override
  DateTime get lastActivityAt => thread.lastReplyAt;
}

final class ChannelPostInboxItem extends InboxItem {
  const ChannelPostInboxItem({required this.candidate, super.postponedAt});

  final InboxPostCandidate candidate;

  Post get post => candidate.post;
  @override
  String get key => 'post:${post.id}';
  @override
  List<String> get postIds => List<String>.unmodifiable(<String>[post.id]);
  @override
  Set<String> get threadRootIds => const <String>{};
  @override
  DateTime get lastActivityAt => post.sentAt;
}

final class DirectMessageBundleInboxItem extends InboxItem {
  DirectMessageBundleInboxItem({
    required this.channelId,
    required this.authorId,
    required this.automationClass,
    required Iterable<InboxPostCandidate> messages,
    super.postponedAt,
  }) : messages = UnmodifiableListView<InboxPostCandidate>(messages.toList()) {
    assert(
      this.messages.isNotEmpty,
      'A direct-message bundle cannot be empty.',
    );
  }

  final String channelId;
  final String authorId;
  final InboxAutomationClass automationClass;
  final List<InboxPostCandidate> messages;

  @override
  String get key => 'direct:$channelId:${messages.first.post.id}';
  @override
  List<String> get postIds => List<String>.unmodifiable(
    messages.map((InboxPostCandidate it) => it.post.id),
  );
  @override
  Set<String> get threadRootIds => const <String>{};
  @override
  DateTime get lastActivityAt => messages.last.post.sentAt;

  DirectMessageBundleInboxItem retainingPostIds(Set<String> ids) =>
      DirectMessageBundleInboxItem(
        channelId: channelId,
        authorId: authorId,
        automationClass: automationClass,
        messages: messages.where(
          (InboxPostCandidate item) => ids.contains(item.post.id),
        ),
        postponedAt: postponedAt,
      );
}

/// The presentation-ready result of a single atomic Inbox reconciliation.
final class InboxSnapshot {
  InboxSnapshot({
    Iterable<InboxItem> newItems = const <InboxItem>[],
    Iterable<InboxItem> postponedItems = const <InboxItem>[],
    this.builtAt,
    this.hasIncompleteMentionReconstruction = false,
  }) : newItems = UnmodifiableListView<InboxItem>(newItems.toList()),
       postponedItems = UnmodifiableListView<InboxItem>(
         postponedItems.toList(),
       );

  final List<InboxItem> newItems;
  final List<InboxItem> postponedItems;
  final DateTime? builtAt;
  final bool hasIncompleteMentionReconstruction;

  int get badgeCount => newItems.length + postponedItems.length;
}
