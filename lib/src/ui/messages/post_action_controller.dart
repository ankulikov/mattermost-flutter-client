import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/post_action.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

typedef PostActionControlKey = ({
  String scopeId,
  String postId,
  String actionId,
});

final class PostActionControlState {
  const PostActionControlState({this.isLoading = false, this.error});
  final bool isLoading;
  final Object? error;
}

/// Volatile, auto-disposed state for exactly one post/action control.
final class PostActionControlController
    extends Notifier<PostActionControlState> {
  PostActionControlController(this._key);

  final PostActionControlKey _key;

  @override
  PostActionControlState build() => const PostActionControlState();

  Future<PostActionResult?> submit({
    required RichAttachmentAction action,
    String? selectedOption,
  }) async {
    final AuthSession? session = ref.read(authSessionProvider);
    if (state.isLoading || session == null) return null;
    state = const PostActionControlState(isLoading: true);
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
      state = const PostActionControlState();
      return result;
    } on Object catch (error) {
      state = PostActionControlState(error: error);
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
