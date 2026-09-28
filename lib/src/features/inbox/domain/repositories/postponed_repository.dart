import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';

/// The observable result of one postponed-preference mutation.
///
/// A request covering more than one server batch is not atomic. When a later
/// batch fails, [confirmed] contains only the batches known to have completed
/// and [requiresReconciliation] tells the caller not to project the entire
/// request optimistically. It deliberately contains no transport error or
/// post content.
final class PostponedBatchOutcome {
  PostponedBatchOutcome({
    required Iterable<PostponedReference> requested,
    required Iterable<PostponedReference> confirmed,
    required this.requiresReconciliation,
  }) : requested = List<PostponedReference>.unmodifiable(requested),
       confirmed = List<PostponedReference>.unmodifiable(confirmed);

  factory PostponedBatchOutcome.confirmed(
    Iterable<PostponedReference> references,
  ) => PostponedBatchOutcome(
    requested: references,
    confirmed: references,
    requiresReconciliation: false,
  );

  final List<PostponedReference> requested;
  final List<PostponedReference> confirmed;
  final bool requiresReconciliation;

  bool get isFullyConfirmed => !requiresReconciliation;
}

/// Raised by the legacy void API when one or more batches completed.
///
/// New Inbox callers use [PostponedBatchOutcome] and reconcile server truth.
/// Keeping this type content-free prevents old callers from silently claiming
/// that an incomplete multi-batch mutation succeeded.
final class PostponedBatchReconciliationRequired implements Exception {
  const PostponedBatchReconciliationRequired();
}

abstract class PostponedRepository {
  const PostponedRepository();

  Future<PostponedReferencesSnapshot> load({required AuthSession session});

  Future<void> save({
    required AuthSession session,
    required List<PostponedReference> references,
  });

  /// Saves references with explicit semantics for a partial multi-batch run.
  ///
  /// Defaulting to the existing operation keeps simple/offline implementations
  /// source-compatible. Network implementations should override this to report
  /// exactly which batches were confirmed.
  Future<PostponedBatchOutcome> saveWithOutcome({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {
    await save(session: session, references: references);
    return PostponedBatchOutcome.confirmed(references);
  }

  Future<void> remove({
    required AuthSession session,
    required List<PostponedReference> references,
  });

  /// Removes references with explicit semantics for a partial multi-batch run.
  Future<PostponedBatchOutcome> removeWithOutcome({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {
    await remove(session: session, references: references);
    return PostponedBatchOutcome.confirmed(references);
  }
}
