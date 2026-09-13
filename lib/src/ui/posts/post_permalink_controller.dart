import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/post_navigation.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';

/// Resolves the immutable destination identified by a post permalink route.
///
/// The controller owns a request scope for one route entry. Disposing the
/// route cancels the in-flight request, and every late completion is ignored.
final class PostPermalinkController
    extends AsyncNotifier<PostNavigationTarget> {
  PostPermalinkController(
    this.postId,
    this._sessionProvider,
    this._repositoryProvider,
  );

  /// The only permalink data stored in route state.
  final String postId;
  final Provider<AuthSession?> _sessionProvider;
  final Provider<PostRepository> _repositoryProvider;

  RequestCancellation? _cancellation;
  AuthSession? _session;
  PostRepository? _repository;
  int _resolutionGeneration = 0;
  bool _retrying = false;

  @override
  Future<PostNavigationTarget> build() async {
    _cancellation?.cancel();
    final int generation = ++_resolutionGeneration;
    final RequestCancellation cancellation = RequestCancellation();
    _cancellation = cancellation;
    ref.onDispose(() {
      cancellation.cancel();
      if (generation == _resolutionGeneration) {
        _resolutionGeneration += 1;
      }
    });

    final AuthSession? session = ref.watch(_sessionProvider);
    if (session == null) {
      _session = null;
      _repository = null;
      throw StateError('No active Mattermost session');
    }
    final PostRepository repository = ref.watch(_repositoryProvider);
    _session = session;
    _repository = repository;
    return _resolve(
      session: session,
      repository: repository,
      cancellation: cancellation,
      generation: generation,
    );
  }

  /// Restarts resolution after an initial failure without retaining stale data.
  Future<void> retry() async {
    final AuthSession? session = _session;
    final PostRepository? repository = _repository;
    if (_retrying || session == null || repository == null) return;

    final RequestCancellation? cancellation = _cancellation;
    if (cancellation == null) return;
    final int generation = ++_resolutionGeneration;
    _retrying = true;
    state = const AsyncLoading<PostNavigationTarget>();
    try {
      final PostNavigationTarget target = await _resolve(
        session: session,
        repository: repository,
        cancellation: cancellation,
        generation: generation,
      );
      if (_isCurrent(cancellation, generation)) {
        state = AsyncData<PostNavigationTarget>(target);
      }
    } on Object catch (error, stackTrace) {
      if (_isCurrent(cancellation, generation)) {
        state = AsyncError<PostNavigationTarget>(error, stackTrace);
      }
    } finally {
      if (generation == _resolutionGeneration) _retrying = false;
    }
  }

  Future<PostNavigationTarget> _resolve({
    required AuthSession session,
    required PostRepository repository,
    required RequestCancellation cancellation,
    required int generation,
  }) async {
    final PostNavigationTarget target = await cancellation.run(
      () =>
          repository.resolveNavigationTarget(session: session, postId: postId),
    );
    if (!_isCurrent(cancellation, generation)) {
      throw const RequestCancelledException(null);
    }
    return target;
  }

  bool _isCurrent(RequestCancellation cancellation, int generation) =>
      !cancellation.isCancelled && generation == _resolutionGeneration;
}
