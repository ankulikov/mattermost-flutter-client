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
    postponedItems: _sortNewestFirst(postponed),
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
      if (byActivity != 0) return byActivity;
      final DateTime firstPostponedAt = first.postponedAt ?? DateTime(0);
      final DateTime secondPostponedAt = second.postponedAt ?? DateTime(0);
      final int byPostponedAt = secondPostponedAt.compareTo(firstPostponedAt);
      return byPostponedAt != 0
          ? byPostponedAt
          : first.key.compareTo(second.key);
    });
  return List<InboxItem>.unmodifiable(sorted);
}
