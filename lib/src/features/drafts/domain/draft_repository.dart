import 'package:mattermost_flutter/src/features/drafts/domain/draft.dart';

/// A transport failure safe for the presentation layer to classify.
final class DraftSyncException implements Exception {
  const DraftSyncException({
    required this.retryable,
    this.retryAfter,
    this.unsupported = false,
  });
  final bool retryable;
  final Duration? retryAfter;
  final bool unsupported;
}

abstract interface class DraftRepository {
  Future<List<Draft>> listTeamDrafts(String teamId);
  Future<Draft?> saveDraft(Draft draft);
  Future<void> deleteDraft({required String channelId, String? rootId});
}
