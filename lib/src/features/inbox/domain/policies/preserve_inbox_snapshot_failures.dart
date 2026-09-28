import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_completeness.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/reconcile_queues.dart';

/// Retains only the parts of [previous] whose authoritative source failed in
/// [incoming].
///
/// A refresh can therefore publish newly fetched data while avoiding a
/// misleading empty section when one independent source is temporarily
/// unavailable. The resulting snapshot retains the incoming failure metadata
/// and completeness; a later successful refresh replaces the retained data.
InboxSnapshot preserveInboxSnapshotFailures({
  required InboxSnapshot previous,
  required InboxSnapshot incoming,
}) {
  final Set<InboxSourceScope> failedScopes = incoming.sourceFailures
      .map((InboxSourceFailure failure) => failure.scope)
      .toSet();
  if (failedScopes.isEmpty) return incoming;

  final List<InboxItem> retainedNewItems = previous.newItems
      .where((InboxItem item) => _belongsToFailedNewSource(item, failedScopes))
      .toList(growable: false);
  final List<InboxItem> retainedPostponedItems =
      failedScopes.contains(InboxSourceScope.postponed)
      ? previous.postponedItems
      : const <InboxItem>[];
  final InboxSnapshot reconciled = reconcileQueues(
    newItems: <InboxItem>[...incoming.newItems, ...retainedNewItems],
    postponedItems: <InboxItem>[
      ...incoming.postponedItems,
      ...retainedPostponedItems,
    ],
    builtAt: incoming.builtAt,
  );
  return InboxSnapshot(
    newItems: reconciled.newItems,
    postponedItems: reconciled.postponedItems,
    builtAt: incoming.builtAt,
    completeness: incoming.completeness,
    diagnosticsCodes: incoming.diagnosticsCodes,
    sourceFailures: incoming.sourceFailures,
  );
}

bool _belongsToFailedNewSource(
  InboxItem item,
  Set<InboxSourceScope> failedScopes,
) => switch (item) {
  ThreadInboxItem() => failedScopes.contains(InboxSourceScope.followedThreads),
  ChannelPostInboxItem() || DirectMessageBundleInboxItem() =>
    failedScopes.contains(InboxSourceScope.unreadChannelPosts),
  UnavailablePostponedInboxItem() => failedScopes.contains(
    InboxSourceScope.postponed,
  ),
};
