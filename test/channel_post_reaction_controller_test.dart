import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/ui/posts/channel_posts_controller.dart';

void main() {
  test('adds and removes the current user reaction optimistically', () async {
    final _PostRepository posts = _PostRepository();
    final Provider<AuthSession?> sessionProvider = Provider<AuthSession?>((_) {
      return AuthSession(
        serverUrl: Uri.parse('https://chat.example.com'),
        userId: 'me',
        username: 'current',
      );
    });
    final Provider<PostRepository> postsProvider = Provider<PostRepository>(
      (_) => posts,
    );
    final AsyncNotifierProvider<ChannelPostsController, ChannelPostsViewState>
    controllerProvider =
        AsyncNotifierProvider<ChannelPostsController, ChannelPostsViewState>(
          () => ChannelPostsController(
            'channel-1',
            sessionProvider,
            postsProvider,
          ),
        );
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(controllerProvider.future);

    final ChannelPostsController controller = container.read(
      controllerProvider.notifier,
    );
    expect(
      await controller.toggleReaction(
        postId: 'post-1',
        emojiName: 'party_parrot',
      ),
      isTrue,
    );
    PostReaction reaction = container
        .read(controllerProvider)
        .requireValue
        .posts
        .single
        .reactions
        .single;
    expect(reaction.count, 3);
    expect(reaction.reactedByCurrentUser, isTrue);
    expect(posts.added, <String>['post-1:party_parrot']);

    expect(
      await controller.toggleReaction(
        postId: 'post-1',
        emojiName: 'party_parrot',
      ),
      isTrue,
    );
    reaction = container
        .read(controllerProvider)
        .requireValue
        .posts
        .single
        .reactions
        .single;
    expect(reaction.count, 2);
    expect(reaction.reactedByCurrentUser, isFalse);
    expect(posts.removed, <String>['post-1:party_parrot']);

    posts.failAdd = true;
    expect(
      await controller.toggleReaction(
        postId: 'post-1',
        emojiName: 'party_parrot',
      ),
      isFalse,
    );
    reaction = container
        .read(controllerProvider)
        .requireValue
        .posts
        .single
        .reactions
        .single;
    expect(reaction.count, 2);
    expect(reaction.reactedByCurrentUser, isFalse);
  });
}

final class _PostRepository extends PostRepository {
  final List<String> added = <String>[];
  final List<String> removed = <String>[];
  bool failAdd = false;

  @override
  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  }) async => ChannelPostPage(
    posts: <ChannelPost>[
      ChannelPost(
        id: 'post-1',
        channelId: channelId,
        author: const PostAuthor(id: 'ada', displayName: 'Ada'),
        sentAt: DateTime.fromMillisecondsSinceEpoch(1),
        message: 'Hello',
        reactions: const <PostReaction>[
          PostReaction(
            emoji: ':party_parrot:',
            emojiName: 'party_parrot',
            count: 2,
          ),
        ],
      ),
    ],
  );

  @override
  Future<ChannelPostPage> loadOlder({
    required AuthSession session,
    required String channelId,
    required String beforePostId,
  }) async => const ChannelPostPage();

  @override
  Future<void> addReaction({
    required AuthSession session,
    required String postId,
    required String emojiName,
  }) async {
    if (failAdd) throw StateError('reaction rejected');
    added.add('$postId:$emojiName');
  }

  @override
  Future<void> removeReaction({
    required AuthSession session,
    required String postId,
    required String emojiName,
  }) async => removed.add('$postId:$emojiName');
}
