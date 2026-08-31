import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/repositories/message_sender.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/reaction_repository.dart';
import 'package:mattermost_flutter/src/ui/posts/channel_posts_controller.dart';

void main() {
  test('adds and removes the current user reaction optimistically', () async {
    final _ReactionRepository reactions = _ReactionRepository();
    final Provider<AuthSession?> sessionProvider = Provider<AuthSession?>((_) {
      return AuthSession(
        serverUrl: Uri.parse('https://chat.example.com'),
        userId: 'me',
        username: 'current',
      );
    });
    final Provider<ChannelPostRepository> postsProvider =
        Provider<ChannelPostRepository>((_) => const _PostRepository());
    final Provider<MessageSender> senderProvider = Provider<MessageSender>(
      (_) => _MessageSender(),
    );
    final Provider<ReactionRepository> reactionsProvider =
        Provider<ReactionRepository>((_) => reactions);
    final AsyncNotifierProvider<ChannelPostsController, ChannelPostsViewState>
    controllerProvider =
        AsyncNotifierProvider<ChannelPostsController, ChannelPostsViewState>(
          () => ChannelPostsController(
            'channel-1',
            sessionProvider,
            postsProvider,
            senderProvider,
            reactionsProvider,
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
    expect(reactions.added, <String>['post-1:party_parrot']);

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
    expect(reactions.removed, <String>['post-1:party_parrot']);

    reactions.failAdd = true;
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

final class _PostRepository implements ChannelPostRepository {
  const _PostRepository();

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
}

final class _ReactionRepository implements ReactionRepository {
  final List<String> added = <String>[];
  final List<String> removed = <String>[];
  bool failAdd = false;

  @override
  Future<void> add({
    required AuthSession session,
    required String postId,
    required String emojiName,
  }) async {
    if (failAdd) throw StateError('reaction rejected');
    added.add('$postId:$emojiName');
  }

  @override
  Future<void> remove({
    required AuthSession session,
    required String postId,
    required String emojiName,
  }) async => removed.add('$postId:$emojiName');
}

final class _MessageSender implements MessageSender {
  @override
  Future<ChannelPost> sendText({
    required AuthSession session,
    required String channelId,
    required String message,
    required String pendingPostId,
    String rootPostId = '',
  }) => throw UnimplementedError();
}
