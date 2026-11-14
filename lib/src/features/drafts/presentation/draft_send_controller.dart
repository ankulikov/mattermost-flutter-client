import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft.dart';
import 'package:mattermost_flutter/src/features/drafts/presentation/drafts_controller.dart';

enum DraftSendPhase { sending, failed, cleanupPending, unsupported }

final class DraftSendStatus {
  const DraftSendStatus(this.phase, this.draft, this.pendingPostId);
  final DraftSendPhase phase;
  final Draft draft;
  final String pendingPostId;
}

/// Session-scoped card submissions. A successful post is never retried as a post.
final class DraftSendController
    extends Notifier<Map<DraftKey, DraftSendStatus>> {
  DraftSendController(
    this._sessionProvider,
    this._postProvider,
    this._draftsProvider,
  );
  final Provider<AuthSession?> _sessionProvider;
  final Provider<PostRepository> _postProvider;
  final NotifierProvider<DraftsController, DraftsState> _draftsProvider;
  int _generation = 0;

  @override
  Map<DraftKey, DraftSendStatus> build() {
    ref.watch(_sessionProvider);
    _generation++;
    ref.onDispose(() => _generation++);
    return {};
  }

  Future<void> send(DraftKey key) async {
    final current = state[key];
    if (current?.phase == DraftSendPhase.sending) return;
    final session = ref.read(_sessionProvider);
    final entry = ref.read(_draftsProvider).entries[key];
    final draft = entry?.draft;
    if (session == null || draft == null || entry?.conflict != null) return;
    final generation = _generation;
    if (current?.phase == DraftSendPhase.cleanupPending) {
      state = {
        ...state,
        key: DraftSendStatus(
          DraftSendPhase.sending,
          current!.draft,
          current.pendingPostId,
        ),
      };
      await _cleanup(key, current.draft, current.pendingPostId, generation);
      return;
    }
    final id =
        current?.phase == DraftSendPhase.failed &&
            _sameContent(current!.draft, draft)
        ? current.pendingPostId
        : 'flutter:${DateTime.now().microsecondsSinceEpoch}:${draft.channelId}';
    if ((draft.type?.isNotEmpty ?? false) ||
        (draft.props?.isNotEmpty ?? false) ||
        (draft.priority?.isNotEmpty ?? false)) {
      state = {
        ...state,
        key: DraftSendStatus(DraftSendPhase.unsupported, draft, id),
      };
      return;
    }
    if (draft.message.trim().isEmpty && draft.fileIds.isEmpty) return;
    state = {...state, key: DraftSendStatus(DraftSendPhase.sending, draft, id)};
    try {
      await ref
          .read(_postProvider)
          .sendPost(
            session: session,
            channelId: draft.channelId,
            rootPostId: draft.rootId ?? '',
            message: draft.message,
            pendingPostId: id,
            fileIds: draft.fileIds,
          );
    } catch (_) {
      if (generation == _generation) {
        state = {
          ...state,
          key: DraftSendStatus(DraftSendPhase.failed, draft, id),
        };
      }
      return;
    }
    if (generation != _generation) return;
    await _cleanup(key, draft, id, generation);
  }

  Future<void> _cleanup(
    DraftKey key,
    Draft draft,
    String id,
    int generation,
  ) async {
    final success = await ref
        .read(_draftsProvider.notifier)
        .deleteIfUnchanged(key, draft);
    if (generation != _generation) return;
    final latest = ref.read(_draftsProvider).entries[key]?.draft;
    if (!success && latest != null && _sameContent(latest, draft)) {
      state = {
        ...state,
        key: DraftSendStatus(DraftSendPhase.cleanupPending, draft, id),
      };
    } else {
      state = Map.of(state)..remove(key);
    }
  }

  static bool _sameContent(Draft a, Draft b) =>
      a.message == b.message &&
      a.fileIds.length == b.fileIds.length &&
      List.generate(
        a.fileIds.length,
        (i) => a.fileIds[i] == b.fileIds[i],
      ).every((equal) => equal);
}
