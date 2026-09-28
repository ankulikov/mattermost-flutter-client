import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_completeness.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_settings.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_source_result.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/canonicalize_inbox_candidates.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/group_direct_messages.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/reconcile_queues.dart';

/// Atomically joins independent Inbox source results into one projection.
///
/// Source adapters own transport and hydration. This domain boundary owns the
/// shared precedence, direct-message grouping, queue exclusivity, sort order,
/// completeness, and content-free diagnostics semantics.
final class InboxProjectionAssembler {
  const InboxProjectionAssembler();

  InboxSnapshot assemble({
    required Iterable<InboxSourceResult> sources,
    DateTime? builtAt,
    InboxDirectGroupingSettings directGrouping =
        const InboxDirectGroupingSettings(),
  }) {
    final List<InboxSourceResult> results = sources.toList(growable: false);
    final InboxSourceSnapshot candidates = InboxSourceSnapshot(
      threads: results.expand(
        (InboxSourceResult source) => source.candidates.threads,
      ),
      posts: results.expand(
        (InboxSourceResult source) => source.candidates.posts,
      ),
    );
    final List<InboxItem> newItems = groupDirectMessages(
      canonicalizeInboxCandidates(candidates),
      directGrouping: directGrouping,
    );
    final InboxSnapshot reconciled = reconcileQueues(
      newItems: newItems,
      postponedItems: results.expand(
        (InboxSourceResult source) => source.postponedItems,
      ),
      builtAt: builtAt,
    );
    return InboxSnapshot(
      newItems: reconciled.newItems,
      postponedItems: reconciled.postponedItems,
      builtAt: builtAt,
      completeness: InboxCompleteness.mostLimited(
        results.map((InboxSourceResult source) => source.completeness),
      ),
      diagnosticsCodes: results.expand(
        (InboxSourceResult source) => source.diagnosticsCodes,
      ),
      sourceFailures: results.expand(
        (InboxSourceResult source) => source.sourceFailures,
      ),
    );
  }
}
