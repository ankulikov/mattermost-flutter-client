import 'dart:collection';

import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_completeness.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';

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
    required this.channel,
    required this.teamId,
    this.rootAttentionReason,
    this.reactivatesPostponed = false,
    super.postponedAt,
  });

  final FollowedThread thread;
  final SidebarChannel channel;
  final String teamId;
  final InboxAttentionReason? rootAttentionReason;
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

/// A durable postponed reference whose server content cannot be displayed.
///
/// The item deliberately contains no hydrated post, author, or channel data.
/// Keeping the original reference lets the user explicitly remove it without
/// silently deleting a server preference that may be temporarily inaccessible.
final class UnavailablePostponedInboxItem extends InboxItem {
  UnavailablePostponedInboxItem({required this.reference})
    : super(postponedAt: reference.addedAt);

  final PostponedReference reference;

  @override
  String get key =>
      'postponed-unavailable:${reference.kind.name}:${reference.canonicalId}';

  @override
  List<String> get postIds =>
      List<String>.unmodifiable(<String>[reference.postId]);

  @override
  Set<String> get threadRootIds =>
      reference.kind == PostponedReferenceKind.thread
      ? Set<String>.unmodifiable(<String>{reference.postId})
      : const <String>{};

  @override
  DateTime get lastActivityAt => reference.addedAt;
}

/// The presentation-ready result of a single atomic Inbox reconciliation.
final class InboxSnapshot {
  InboxSnapshot({
    Iterable<InboxItem> newItems = const <InboxItem>[],
    Iterable<InboxItem> postponedItems = const <InboxItem>[],
    this.builtAt,
    InboxCompleteness completeness = InboxCompleteness.exact,
    @Deprecated('Use completeness instead.')
    bool? hasIncompleteMentionReconstruction,
    Iterable<InboxSourceDiagnosticCode> diagnosticsCodes =
        const <InboxSourceDiagnosticCode>[],
    Iterable<InboxSourceFailure> sourceFailures = const <InboxSourceFailure>[],
  }) : newItems = UnmodifiableListView<InboxItem>(newItems.toList()),
       postponedItems = UnmodifiableListView<InboxItem>(
         postponedItems.toList(),
       ),
       completeness =
           completeness == InboxCompleteness.exact &&
               hasIncompleteMentionReconstruction == true
           ? InboxCompleteness.approximateMentions
           : completeness,
       diagnosticsCodes = UnmodifiableSetView<InboxSourceDiagnosticCode>(
         Set<InboxSourceDiagnosticCode>.of(diagnosticsCodes),
       ),
       sourceFailures = UnmodifiableSetView<InboxSourceFailure>(
         Set<InboxSourceFailure>.of(sourceFailures),
       );

  final List<InboxItem> newItems;
  final List<InboxItem> postponedItems;
  final DateTime? builtAt;
  final InboxCompleteness completeness;
  final Set<InboxSourceDiagnosticCode> diagnosticsCodes;
  final Set<InboxSourceFailure> sourceFailures;

  /// Legacy bridge for callers that only understood historical mention gaps.
  @Deprecated('Use completeness instead.')
  bool get hasIncompleteMentionReconstruction =>
      completeness == InboxCompleteness.approximateMentions;

  /// Whether Inbox should draw attention in the app navigation.
  ///
  /// Postponed items are intentionally excluded: they were explicitly removed
  /// from the new-message queue by the user.
  bool get hasNewItems => newItems.isNotEmpty;

  /// Counts individual messages as they are presented in an Inbox tab.
  ///
  /// A direct-message bundle can contain several messages, while a thread is
  /// represented by its root post and therefore counts as one item here.
  int get newMessageCount => _messageCount(newItems);
  int get postponedMessageCount => _messageCount(postponedItems);

  int _messageCount(Iterable<InboxItem> items) => items.fold<int>(
    0,
    (int count, InboxItem item) => count + item.postIds.length,
  );
}
