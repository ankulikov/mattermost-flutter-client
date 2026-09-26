import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/ui/posts/channel_posts_controller.dart';

void main() {
  test('focuses an historical window and pages both directions', () async {
    final _NavigationPostRepository repository = _NavigationPostRepository();
    final (:container, :provider) = _container(repository);
    addTearDown(container.dispose);
    await container.read(provider.future);
    final ChannelPostsController controller = container.read(provider.notifier);

    await controller.focusOn('focus');
    ChannelPostsViewState state = container.read(provider).requireValue;
    expect(state.focusPostId, 'focus');
    expect(state.posts.map((Post post) => post.id), <String>[
      'older',
      'focus',
      'newer',
    ]);
    expect(state.hasOlder, isTrue);
    expect(state.hasNewer, isTrue);

    await controller.loadOlder();
    await controller.loadNewer();
    state = container.read(provider).requireValue;
    expect(repository.beforeCursor, 'older');
    expect(repository.afterCursor, 'newer');
    expect(state.posts.map((Post post) => post.id), <String>[
      'oldest',
      'older',
      'focus',
      'newer',
      'newest',
    ]);
    expect(state.hasOlder, isFalse);
    expect(state.hasNewer, isFalse);
  });

  test(
    'keeps useful channel data when focus fails and supports retry',
    () async {
      final _NavigationPostRepository repository = _NavigationPostRepository()
        ..failAround = true;
      final (:container, :provider) = _container(repository);
      addTearDown(container.dispose);
      await container.read(provider.future);
      final ChannelPostsController controller = container.read(
        provider.notifier,
      );

      await controller.focusOn('focus');
      ChannelPostsViewState state = container.read(provider).requireValue;
      expect(state.posts.single.id, 'recent');
      expect(state.focusStatus, isA<OperationFailed>());

      repository.failAround = false;
      await controller.retryFocus();
      state = container.read(provider).requireValue;
      expect(state.focusStatus, isA<OperationIdle>());
      expect(state.focusPostId, 'focus');
    },
  );
}

({
  ProviderContainer container,
  AsyncNotifierProvider<ChannelPostsController, ChannelPostsViewState> provider,
})
_container(PostRepository repository) {
  final Provider<AuthSession?> sessionProvider = Provider<AuthSession?>((_) {
    return AuthSession(
      serverUrl: Uri.parse('https://chat.example.com'),
      userId: 'me',
      username: 'current',
    );
  });
  final Provider<PostRepository> repositoryProvider = Provider<PostRepository>(
    (_) => repository,
  );
  final provider =
      AsyncNotifierProvider<ChannelPostsController, ChannelPostsViewState>(
        () => ChannelPostsController(
          'channel-1',
          sessionProvider,
          repositoryProvider,
        ),
      );
  return (container: ProviderContainer(), provider: provider);
}

final class _NavigationPostRepository extends PostRepository {
  bool failAround = false;
  String? beforeCursor;
  String? afterCursor;

  Post _post(String id, int minute) => Post(
    id: id,
    channelId: 'channel-1',
    author: const PostAuthor(id: 'ada', displayName: 'Ada'),
    sentAt: DateTime(2026, 9, 11, 10, minute),
    message: id,
  );

  @override
  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  }) async => ChannelPostPage(posts: <Post>[_post('recent', 50)]);

  @override
  Future<ChannelPostPage> loadAround({
    required AuthSession session,
    required String channelId,
    required String postId,
  }) async {
    if (failAround) throw StateError('historical window failed');
    return ChannelPostPage(
      posts: <Post>[_post('older', 20), _post('focus', 30), _post('newer', 40)],
      beforePostId: 'older',
      afterPostId: 'newer',
      hasOlder: true,
      hasNewer: true,
    );
  }

  @override
  Future<ChannelPostPage> loadOlder({
    required AuthSession session,
    required String channelId,
    required String beforePostId,
  }) async {
    beforeCursor = beforePostId;
    return ChannelPostPage(posts: <Post>[_post('oldest', 10)]);
  }

  @override
  Future<ChannelPostPage> loadNewer({
    required AuthSession session,
    required String channelId,
    required String afterPostId,
  }) async {
    afterCursor = afterPostId;
    return ChannelPostPage(posts: <Post>[_post('newest', 50)]);
  }
}
