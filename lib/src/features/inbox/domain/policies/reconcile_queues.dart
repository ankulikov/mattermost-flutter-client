import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';

/// Enforces the exclusivity invariant between the New and Postponed queues.
///
/// A new explicit mention reactivates a postponed thread; all other postponed
/// references suppress their matching New post or thread.
InboxSnapshot reconcileQueues({
  required Iterable<InboxItem> newItems,
  required Iterable<InboxItem> postponedItems,
  DateTime? builtAt,
  bool hasIncompleteMentionReconstruction = false,
}) {
  final List<InboxItem> postponed = _deduplicate(postponedItems);
  final Set<String> postponedPostIds = postponed
      .expand((InboxItem item) => item.postIds)
      .toSet();
  final Set<String> postponedThreadIds = postponed
      .expand((InboxItem item) => item.threadRootIds)
      .toSet();

  final List<InboxItem> reconciledNew = <InboxItem>[];
  for (final InboxItem item in _deduplicate(newItems)) {
    if (item is ThreadInboxItem &&
        item.reactivatesPostponed &&
        item.threadRootIds.any(postponedThreadIds.contains)) {
      postponed.removeWhere(
        (InboxItem postponedItem) =>
            postponedItem.threadRootIds.any(item.threadRootIds.contains),
      );
      reconciledNew.add(item);
      continue;
    }
    if (item.threadRootIds.any(postponedThreadIds.contains)) continue;

    final Set<String> remainingPostIds = item.postIds
        .where((String postId) => !postponedPostIds.contains(postId))
        .toSet();
    if (remainingPostIds.isEmpty) continue;
    reconciledNew.add(_retainPosts(item, remainingPostIds));
  }

  return InboxSnapshot(
    newItems: _sortNewestFirst(reconciledNew),
    postponedItems: List<InboxItem>.unmodifiable(
      postponed..sort(comparePostponedInboxItems),
    ),
    builtAt: builtAt,
    hasIncompleteMentionReconstruction: hasIncompleteMentionReconstruction,
  );
}

InboxItem _retainPosts(InboxItem item, Set<String> ids) => switch (item) {
  DirectMessageBundleInboxItem() => item.retainingPostIds(ids),
  _ => item,
};

List<InboxItem> _deduplicate(Iterable<InboxItem> items) {
  final Map<String, InboxItem> byKey = <String, InboxItem>{};
  for (final InboxItem item in items) {
    byKey.putIfAbsent(item.key, () => item);
  }
  return byKey.values.toList();
}

List<InboxItem> _sortNewestFirst(Iterable<InboxItem> items) {
  final List<InboxItem> sorted = items.toList()
    ..sort((InboxItem first, InboxItem second) {
      final int byActivity = second.lastActivityAt.compareTo(
        first.lastActivityAt,
      );
      return byActivity != 0 ? byActivity : first.key.compareTo(second.key);
    });
  return List<InboxItem>.unmodifiable(sorted);
}

/// Orders saved messages by when they entered Postponed, newest first.
int comparePostponedInboxItems(InboxItem first, InboxItem second) {
  final DateTime? firstAddedAt = first.postponedAt;
  final DateTime? secondAddedAt = second.postponedAt;
  if (firstAddedAt != null && secondAddedAt != null) {
    final int byAddedAt = secondAddedAt.compareTo(firstAddedAt);
    if (byAddedAt != 0) return byAddedAt;
  } else if (firstAddedAt != null || secondAddedAt != null) {
    return firstAddedAt != null ? -1 : 1;
  }
  return first.key.compareTo(second.key);
}
