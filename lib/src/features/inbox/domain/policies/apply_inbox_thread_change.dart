import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/reconcile_queues.dart';

/// Applies one followed-thread delta without rebuilding the full Inbox.
///
/// The reducer only accepts an item hydrated and eligibility-checked by the
/// data layer. A partial payload can still update counters for an existing
/// thread, but never fabricates root/channel content for a new one.
InboxThreadChangeResult applyInboxThreadChange({
  required InboxSnapshot snapshot,
  required InboxRealtimeEvent event,
}) => switch (event) {
  InboxThreadUpdated() => _applyThreadUpdated(snapshot, event),
  InboxThreadFollowChanged() => _applyFollowChanged(snapshot, event),
  InboxThreadReadChanged() => InboxThreadChangeResult(
    snapshot: _removeThread(snapshot, event.rootPostId),
  ),
  _ => InboxThreadChangeResult(snapshot: snapshot),
};

final class InboxThreadChangeResult {
  const InboxThreadChangeResult({
    required this.snapshot,
    this.recoveryRequired = false,
  });

  final InboxSnapshot snapshot;
  final bool recoveryRequired;
}

InboxThreadChangeResult _applyThreadUpdated(
  InboxSnapshot snapshot,
  InboxThreadUpdated event,
) {
  if (event.isFollowing == false || event.isInboxEligible == false) {
    return InboxThreadChangeResult(
      snapshot: _removeThread(snapshot, event.rootPostId),
    );
  }

  final InboxThreadCandidate? candidate = event.candidate;
  if (candidate != null) {
    return InboxThreadChangeResult(
      snapshot: _upsertThread(
        snapshot,
        candidate,
        reactivatesPostponed: event.reactivatePostponed,
      ),
    );
  }

  final bool canUpdateExistingCounters =
      event.unreadReplies != null || event.unreadMentions != null;
  if (canUpdateExistingCounters) {
    return InboxThreadChangeResult(
      snapshot: _updateExistingCounters(snapshot, event),
      recoveryRequired: event.recoveryRequired,
    );
  }
  return InboxThreadChangeResult(
    snapshot: snapshot,
    recoveryRequired: event.recoveryRequired,
  );
}

InboxThreadChangeResult _applyFollowChanged(
  InboxSnapshot snapshot,
  InboxThreadFollowChanged event,
) {
  if (event.isFollowing == false) {
    return InboxThreadChangeResult(
      snapshot: _removeThread(snapshot, event.rootPostId),
    );
  }
  final InboxThreadCandidate? candidate = event.candidate;
  return InboxThreadChangeResult(
    snapshot: candidate == null
        ? snapshot
        : _upsertThread(snapshot, candidate, reactivatesPostponed: false),
    recoveryRequired: candidate == null && event.recoveryRequired,
  );
}

InboxSnapshot _upsertThread(
  InboxSnapshot snapshot,
  InboxThreadCandidate candidate, {
  required bool reactivatesPostponed,
}) {
  final String rootPostId = candidate.thread.id;
  final List<InboxItem> newItems =
      snapshot.newItems
          .where(
            (InboxItem item) =>
                item is! ThreadInboxItem || item.thread.id != rootPostId,
          )
          .toList()
        ..add(_itemFrom(candidate, reactivatesPostponed: reactivatesPostponed));
  return _preservingMetadata(
    snapshot,
    reconcileQueues(
      newItems: newItems,
      postponedItems: snapshot.postponedItems,
      builtAt: snapshot.builtAt,
      hasIncompleteMentionReconstruction:
          snapshot.hasIncompleteMentionReconstruction,
    ),
  );
}

InboxSnapshot _updateExistingCounters(
  InboxSnapshot snapshot,
  InboxThreadUpdated event,
) => _copySnapshot(
  snapshot,
  newItems: _replaceCounters(snapshot.newItems, event),
  postponedItems: _replaceCounters(snapshot.postponedItems, event),
);

List<InboxItem> _replaceCounters(
  Iterable<InboxItem> items,
  InboxThreadUpdated event,
) => items
    .map(
      (InboxItem item) => switch (item) {
        ThreadInboxItem(:final thread) when thread.id == event.rootPostId =>
          ThreadInboxItem(
            thread: _withCounters(thread, event),
            channel: item.channel,
            teamId: item.teamId,
            rootAttentionReason: item.rootAttentionReason,
            reactivatesPostponed: item.reactivatesPostponed,
            postponedAt: item.postponedAt,
          ),
        _ => item,
      },
    )
    .toList(growable: false);

FollowedThread _withCounters(FollowedThread thread, InboxThreadUpdated event) =>
    thread.copyWith(
      unreadReplies: event.unreadReplies,
      unreadMentions: event.unreadMentions,
    );

InboxSnapshot _removeThread(InboxSnapshot snapshot, String rootPostId) =>
    _copySnapshot(
      snapshot,
      newItems: _withoutThread(snapshot.newItems, rootPostId),
      postponedItems: _withoutThread(snapshot.postponedItems, rootPostId),
    );

List<InboxItem> _withoutThread(Iterable<InboxItem> items, String rootPostId) =>
    items
        .where(
          (InboxItem item) =>
              item is! ThreadInboxItem || item.thread.id != rootPostId,
        )
        .toList(growable: false);

ThreadInboxItem _itemFrom(
  InboxThreadCandidate candidate, {
  required bool reactivatesPostponed,
}) => ThreadInboxItem(
  thread: candidate.thread,
  channel: candidate.channel,
  teamId: candidate.teamId,
  rootAttentionReason: candidate.rootAttentionReason,
  reactivatesPostponed: reactivatesPostponed,
);

InboxSnapshot _copySnapshot(
  InboxSnapshot snapshot, {
  required Iterable<InboxItem> newItems,
  required Iterable<InboxItem> postponedItems,
}) => InboxSnapshot(
  newItems: newItems,
  postponedItems: postponedItems,
  builtAt: snapshot.builtAt,
  completeness: snapshot.completeness,
  diagnosticsCodes: snapshot.diagnosticsCodes,
  sourceFailures: snapshot.sourceFailures,
);

InboxSnapshot _preservingMetadata(InboxSnapshot previous, InboxSnapshot next) =>
    InboxSnapshot(
      newItems: next.newItems,
      postponedItems: next.postponedItems,
      builtAt: next.builtAt,
      completeness: previous.completeness,
      diagnosticsCodes: previous.diagnosticsCodes,
      sourceFailures: previous.sourceFailures,
    );
