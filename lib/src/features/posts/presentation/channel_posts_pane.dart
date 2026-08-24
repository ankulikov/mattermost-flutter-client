import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';
import 'package:mattermost_flutter/src/features/posts/presentation/channel_posts_controller.dart';
import 'package:mattermost_flutter/src/features/posts/presentation/channel_posts_strings.dart';

class ChannelPostsPane extends ConsumerWidget {
  const ChannelPostsPane({required this.channel, super.key});

  final SidebarChannel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ChannelPost>> posts = ref.watch(
      channelPostsProvider(channel.id),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ChannelHeader(channel: channel),
        const Divider(height: 1),
        Expanded(
          child: posts.when(
            loading: () => const _PostsLoading(),
            error: (Object error, StackTrace stackTrace) => _PostsError(
              onRetry: () => ref.invalidate(channelPostsProvider(channel.id)),
            ),
            data: (List<ChannelPost> items) => items.isEmpty
                ? const Center(child: Text(ChannelPostsStrings.empty))
                : _PostList(channelId: channel.id, posts: items),
          ),
        ),
      ],
    );
  }
}

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({required this.channel});

  final SidebarChannel channel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    child: Row(
      children: <Widget>[
        Icon(_channelIcon(channel.kind), size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            channel.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  IconData _channelIcon(ChannelKind kind) => switch (kind) {
    ChannelKind.publicChannel => Icons.tag,
    ChannelKind.privateChannel => Icons.lock_outline,
    ChannelKind.directMessage => Icons.person_outline,
    ChannelKind.groupMessage => Icons.group_outlined,
  };
}

class _PostsLoading extends StatelessWidget {
  const _PostsLoading();

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      label: ChannelPostsStrings.loading,
      child: const CircularProgressIndicator(),
    ),
  );
}

class _PostsError extends StatelessWidget {
  const _PostsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            ChannelPostsStrings.loadFailed,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text(ChannelPostsStrings.retry),
          ),
        ],
      ),
    ),
  );
}

class _PostList extends StatelessWidget {
  const _PostList({required this.channelId, required this.posts});

  final String channelId;
  final List<ChannelPost> posts;

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: PageStorageKey<String>('channel-posts-$channelId'),
    padding: const EdgeInsets.fromLTRB(10, 12, 10, 24),
    itemCount: posts.length,
    itemBuilder: (BuildContext context, int index) {
      final ChannelPost post = posts[index];
      final bool continuesAuthor =
          index > 0 && posts[index - 1].author.id == post.author.id;
      return _PostRow(
        key: ValueKey<String>(post.id),
        post: post,
        continuesAuthor: continuesAuthor,
      );
    },
  );
}

class _PostRow extends StatelessWidget {
  const _PostRow({
    required this.post,
    required this.continuesAuthor,
    super.key,
  });

  final ChannelPost post;
  final bool continuesAuthor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(post.sentAt));
    return Padding(
      padding: EdgeInsets.only(
        top: continuesAuthor ? 2 : 8,
        bottom: continuesAuthor ? 2 : 4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (continuesAuthor)
            const SizedBox(width: 38)
          else
            _AuthorAvatar(author: post.author),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (!continuesAuthor) ...<Widget>[
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 2,
                    children: <Widget>[
                      Text(
                        post.author.displayName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        time,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                ],
                Text(post.message, style: theme.textTheme.bodyMedium),
                if (post.reactions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Semantics(
                    label: ChannelPostsStrings.reactions,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: post.reactions
                          .map(
                            (PostReaction reaction) =>
                                _ReactionChip(reaction: reaction),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({required this.author});

  final PostAuthor author;

  @override
  Widget build(BuildContext context) {
    final String initials = author.displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .take(2)
        .map((String part) => part[0].toUpperCase())
        .join();
    return Semantics(
      image: true,
      label: author.displayName,
      child: CircleAvatar(
        radius: 19,
        backgroundColor: _avatarColor(author.id),
        foregroundColor: Colors.white,
        child: Text(
          initials,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: Colors.white),
        ),
      ),
    );
  }

  Color _avatarColor(String id) {
    const List<Color> colors = <Color>[
      Color(0xff3f51b5),
      Color(0xff00796b),
      Color(0xffad4b00),
      Color(0xff7b1fa2),
    ];
    final int sum = id.codeUnits.fold(0, (int value, int unit) => value + unit);
    return colors[sum % colors.length];
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.reaction});

  final PostReaction reaction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color background = reaction.reactedByCurrentUser
        ? colors.primaryContainer
        : colors.surfaceContainerHighest;
    final Color border = reaction.reactedByCurrentUser
        ? colors.primary
        : colors.outlineVariant;
    return Semantics(
      label: '${reaction.emoji}: ${reaction.count}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '${reaction.emoji}  ${reaction.count}',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }
}
