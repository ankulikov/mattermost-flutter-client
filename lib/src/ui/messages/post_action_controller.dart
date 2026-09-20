import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/post_action.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment_option.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_action_repository.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

typedef PostActionControlKey = ({
  String scopeId,
  String postId,
  String actionId,
  String channelId,
  String sourceRootPostId,
});

final class PostActionControlState {
  const PostActionControlState({
    this.isLoading = false,
    this.error,
    this.feedback = '',
    this.realtimeUpdatedPost,
  });
  final bool isLoading;
  final Object? error;
  final String feedback;
  final ChannelPost? realtimeUpdatedPost;
}

/// Volatile, auto-disposed state for exactly one post/action control.
final class PostActionControlController
    extends Notifier<PostActionControlState> {
  PostActionControlController(this._key);

  final PostActionControlKey _key;
  StreamSubscription<PostActionPresentationEvent>? _subscription;

  @override
  PostActionControlState build() {
    final PostActionRealtimeCoordinator coordinator = ref.watch(
      postActionRealtimeCoordinatorProvider,
    );
    _subscription = coordinator.events.listen((
      PostActionPresentationEvent event,
    ) {
      switch (event) {
        case PostActionFeedbackReceived(:final key, :final message)
            when key == _key:
          state = PostActionControlState(
            feedback: message,
            realtimeUpdatedPost: state.realtimeUpdatedPost,
          );
        case PostActionRealtimePostReceived(:final post)
            when post.id == _key.postId:
          state = PostActionControlState(
            isLoading: state.isLoading,
            error: state.error,
            feedback: state.feedback,
            realtimeUpdatedPost: post,
          );
        default:
          break;
      }
    });
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
      coordinator.unregister(_key);
    });
    return const PostActionControlState();
  }

  Future<PostActionResult?> submit({
    required RichAttachmentAction action,
    String? selectedOption,
  }) async {
    final AuthSession? session = ref.read(authSessionProvider);
    if (state.isLoading || session == null) return null;
    final PostActionRealtimeCoordinator coordinator = ref.read(
      postActionRealtimeCoordinatorProvider,
    );
    coordinator.register(_key);
    state = PostActionControlState(
      isLoading: true,
      feedback: state.feedback,
      realtimeUpdatedPost: state.realtimeUpdatedPost,
    );
    try {
      final PostActionResult result = await ref
          .read(postActionRepositoryProvider)
          .execute(
            session: session,
            postId: _key.postId,
            actionId: action.id,
            token: action.token,
            selectedOption: selectedOption,
          );
      coordinator.complete(_key);
      state = PostActionControlState(
        feedback: state.feedback,
        realtimeUpdatedPost: state.realtimeUpdatedPost,
      );
      return result;
    } on Object catch (error) {
      coordinator.unregister(_key);
      state = PostActionControlState(
        error: error,
        feedback: state.feedback,
        realtimeUpdatedPost: state.realtimeUpdatedPost,
      );
      return null;
    }
  }
}

final postActionControlProvider = NotifierProvider.autoDispose
    .family<
      PostActionControlController,
      PostActionControlState,
      PostActionControlKey
    >((PostActionControlKey key) => PostActionControlController(key));

sealed class PostActionPresentationEvent {
  const PostActionPresentationEvent();
}

final class PostActionFeedbackReceived extends PostActionPresentationEvent {
  const PostActionFeedbackReceived({required this.key, required this.message});

  final PostActionControlKey key;
  final String message;
}

final class PostActionRealtimePostReceived extends PostActionPresentationEvent {
  const PostActionRealtimePostReceived(this.post);

  final ChannelPost post;
}

final class PostActionRealtimeCoordinator {
  PostActionRealtimeCoordinator({
    required AuthSession? session,
    required PostActionRepository? repository,
  }) {
    if (session != null && repository != null) {
      _subscription = repository
          .watchRealtime(session: session)
          .listen(_onRealtimeEvent);
    }
  }

  static const Duration feedbackWindow = Duration(seconds: 5);

  final StreamController<PostActionPresentationEvent> _events =
      StreamController<PostActionPresentationEvent>.broadcast();
  final List<PostActionControlKey> _pending = <PostActionControlKey>[];
  final Map<PostActionControlKey, Timer> _expiryTimers =
      <PostActionControlKey, Timer>{};
  StreamSubscription<PostActionRealtimeEvent>? _subscription;

  Stream<PostActionPresentationEvent> get events => _events.stream;

  void register(PostActionControlKey key) {
    unregister(key);
    _pending.add(key);
  }

  void complete(PostActionControlKey key) {
    if (!_pending.contains(key)) return;
    _expiryTimers[key]?.cancel();
    _expiryTimers[key] = Timer(feedbackWindow, () => unregister(key));
  }

  void unregister(PostActionControlKey key) {
    _pending.remove(key);
    _expiryTimers.remove(key)?.cancel();
  }

  void _onRealtimeEvent(PostActionRealtimeEvent event) {
    switch (event) {
      case PostActionPostUpdated(:final post):
        _events.add(PostActionRealtimePostReceived(post));
      case PostActionEphemeralFeedback(
        :final channelId,
        :final sourceRootPostId,
        :final message,
      ):
        final int index = _pending.indexWhere(
          (PostActionControlKey key) =>
              key.channelId == channelId &&
              key.sourceRootPostId == sourceRootPostId,
        );
        if (index < 0) return;
        final PostActionControlKey key = _pending.removeAt(index);
        _expiryTimers.remove(key)?.cancel();
        _events.add(PostActionFeedbackReceived(key: key, message: message));
    }
  }

  Future<void> dispose() async {
    for (final Timer timer in _expiryTimers.values) {
      timer.cancel();
    }
    _expiryTimers.clear();
    _pending.clear();
    await _subscription?.cancel();
    await _events.close();
  }
}

final Provider<PostActionRealtimeCoordinator>
postActionRealtimeCoordinatorProvider = Provider<PostActionRealtimeCoordinator>(
  (Ref ref) {
    final AuthSession? session = ref.watch(authSessionProvider);
    final PostActionRealtimeCoordinator coordinator =
        PostActionRealtimeCoordinator(
          session: session,
          repository: session == null
              ? null
              : ref.watch(postActionRepositoryProvider),
        );
    ref.onDispose(() => unawaited(coordinator.dispose()));
    return coordinator;
  },
);

typedef RichAttachmentOptionSearchRequest = ({
  RichAttachmentSelectDataSource dataSource,
  String query,
});

/// A cancel-on-dispose query used by the searchable system select picker.
final richAttachmentOptionsProvider = FutureProvider.autoDispose
    .family<
      List<RichAttachmentSystemOption>,
      RichAttachmentOptionSearchRequest
    >((Ref ref, RichAttachmentOptionSearchRequest request) {
      final AuthSession? session = ref.watch(authSessionProvider);
      if (session == null) return const <RichAttachmentSystemOption>[];
      final RequestCancellation cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      return cancellation.run(
        () => ref
            .watch(richAttachmentOptionRepositoryProvider)
            .search(
              session: session,
              dataSource: request.dataSource,
              query: request.query,
            ),
      );
    });
