import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/ui/app_breakpoints.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';
import 'package:mattermost_flutter/src/features/posts/presentation/channel_posts_controller.dart';
import 'package:mattermost_flutter/src/features/posts/presentation/channel_posts_strings.dart';
import 'package:mattermost_flutter/src/features/threads/presentation/thread_pane.dart';
import 'package:mattermost_flutter/src/features/threads/presentation/thread_strings.dart';

class ChannelPostsPane extends ConsumerStatefulWidget {
  const ChannelPostsPane({required this.channel, super.key});

  final SidebarChannel channel;

  @override
  ConsumerState<ChannelPostsPane> createState() => _ChannelPostsPaneState();
}

class _ChannelPostsPaneState extends ConsumerState<ChannelPostsPane> {
  String? _selectedRootPostId;

  @override
  void didUpdateWidget(covariant ChannelPostsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) {
      _selectedRootPostId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final SidebarChannel channel = widget.channel;
    final AsyncValue<ChannelPostsViewState> posts = ref.watch(
      channelPostsProvider(channel.id),
    );
    final ChannelPostsViewState? viewState = posts.value;
    final Widget channelPane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ChannelHeader(
          channel: channel,
          isLoading: viewState?.isLoadingOlder == true,
        ),
        const Divider(height: 1),
        Expanded(
          child: posts.when(
            loading: () => const _PostsLoading(),
            error: (Object error, StackTrace stackTrace) => _PostsError(
              onRetry: () =>
                  ref.read(channelPostsProvider(channel.id).notifier).retry(),
            ),
            data: (ChannelPostsViewState state) {
              final List<ChannelPost> items = state.posts;
              if (items.isEmpty && state.loadFailed) {
                return _PostsError(
                  onRetry: () => ref
                      .read(channelPostsProvider(channel.id).notifier)
                      .retry(),
                );
              }
              if (items.isEmpty && !state.hasOlder) {
                return const Center(child: Text(ChannelPostsStrings.empty));
              }
              return _PostList(
                channelId: channel.id,
                posts: items,
                isLoadingOlder: state.isLoadingOlder,
                hasOlder: state.hasOlder,
                autoLoadOlder: !state.loadFailed,
                onLoadOlder: () => ref
                    .read(channelPostsProvider(channel.id).notifier)
                    .loadOlder(),
                onOpenThread: (ChannelPost post) {
                  setState(() => _selectedRootPostId = post.id);
                },
              );
            },
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final String? rootPostId = _selectedRootPostId;
        if (rootPostId == null) return channelPane;
        final Widget thread = ThreadPane(
          key: ValueKey<String>('thread-$rootPostId'),
          rootPostId: rootPostId,
          channel: channel,
          onClose: () => setState(() => _selectedRootPostId = null),
        );
        if (constraints.maxWidth >= AppBreakpoints.sideThread) {
          return Row(
            children: <Widget>[
              Expanded(child: channelPane),
              const VerticalDivider(width: 1),
              SizedBox(width: 380, child: thread),
            ],
          );
        }
        return Stack(
          children: <Widget>[
            Positioned.fill(child: channelPane),
            Positioned.fill(child: thread),
          ],
        );
      },
    );
  }
}

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({required this.channel, required this.isLoading});

  final SidebarChannel channel;
  final bool isLoading;

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
        if (isLoading) ...<Widget>[
          const SizedBox(width: 12),
          Semantics(
            label: ChannelPostsStrings.loading,
            child: const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
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

class _PostList extends StatefulWidget {
  const _PostList({
    required this.channelId,
    required this.posts,
    required this.isLoadingOlder,
    required this.hasOlder,
    required this.autoLoadOlder,
    required this.onLoadOlder,
    required this.onOpenThread,
  });

  final String channelId;
  final List<ChannelPost> posts;
  final bool isLoadingOlder;
  final bool hasOlder;
  final bool autoLoadOlder;
  final Future<void> Function() onLoadOlder;
  final ValueChanged<ChannelPost> onOpenThread;

  @override
  State<_PostList> createState() => _PostListState();
}

class _PostListState extends State<_PostList> {
  static const int _maxAutomaticLoads = 20;

  late final ScrollController _controller = ScrollController(
    keepScrollOffset: true,
  )..addListener(_onScroll);
  bool _autoLoadPending = false;
  bool _viewportCheckScheduled = false;
  int _automaticLoadCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeFillViewport();
    });
  }

  @override
  void didUpdateWidget(covariant _PostList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelId != widget.channelId ||
        (oldWidget.isLoadingOlder && !widget.isLoadingOlder)) {
      _autoLoadPending = false;
    }
    if (oldWidget.channelId != widget.channelId) _automaticLoadCount = 0;
    _scheduleViewportCheck();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_controller.position.extentAfter < 160) _requestOlder();
  }

  void _scheduleViewportCheck() {
    if (_viewportCheckScheduled) return;
    _viewportCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportCheckScheduled = false;
      if (mounted) _maybeFillViewport();
    });
  }

  void _maybeFillViewport() {
    if (!widget.autoLoadOlder ||
        _automaticLoadCount >= _maxAutomaticLoads ||
        !_controller.hasClients ||
        !_controller.position.hasContentDimensions) {
      return;
    }
    final ScrollPosition position = _controller.position;
    if (position.maxScrollExtent > position.minScrollExtent + 0.5) return;
    _requestOlder(automatic: true);
  }

  void _requestOlder({bool automatic = false}) {
    if (_autoLoadPending || widget.isLoadingOlder || !widget.hasOlder) return;
    if (automatic) _automaticLoadCount += 1;
    _autoLoadPending = true;
    unawaited(
      widget.onLoadOlder().whenComplete(() {
        if (!mounted) return;
        _autoLoadPending = false;
        _scheduleViewportCheck();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showManualLoad =
        _automaticLoadCount >= _maxAutomaticLoads &&
        widget.hasOlder &&
        !widget.isLoadingOlder;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (ScrollMetricsNotification notification) {
        _scheduleViewportCheck();
        return false;
      },
      child: ListView.builder(
        controller: _controller,
        reverse: true,
        key: PageStorageKey<String>('channel-posts-${widget.channelId}'),
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 24),
        itemCount:
            widget.posts.length +
            (widget.isLoadingOlder || showManualLoad ? 1 : 0),
        itemBuilder: (BuildContext context, int index) {
          if (index == widget.posts.length) {
            if (showManualLoad) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: OutlinedButton(
                    onPressed: _requestOlder,
                    child: const Text(ChannelPostsStrings.loadOlder),
                  ),
                ),
              );
            }
            return Semantics(
              label: ChannelPostsStrings.loadingOlder,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            );
          }
          final int postIndex = widget.posts.length - 1 - index;
          final ChannelPost post = widget.posts[postIndex];
          final bool continuesAuthor =
              postIndex > 0 &&
              widget.posts[postIndex - 1].author.id == post.author.id;
          return _PostRow(
            key: ValueKey<String>(post.id),
            post: post,
            continuesAuthor: continuesAuthor,
            onOpenThread: widget.onOpenThread,
          );
        },
      ),
    );
  }
}

class _PostRow extends StatelessWidget {
  const _PostRow({
    required this.post,
    required this.continuesAuthor,
    required this.onOpenThread,
    super.key,
  });

  final ChannelPost post;
  final bool continuesAuthor;
  final ValueChanged<ChannelPost> onOpenThread;

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
                if (post.replyCount > 0) ...<Widget>[
                  const SizedBox(height: 6),
                  Semantics(
                    button: true,
                    label: ThreadStrings.replyCount(post.replyCount),
                    child: TextButton.icon(
                      onPressed: () => onOpenThread(post),
                      icon: const Icon(Icons.forum_outlined, size: 18),
                      label: Text(_threadSummary(context, post)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(44, 44),
                      ),
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

  String _threadSummary(BuildContext context, ChannelPost post) {
    final String count = ThreadStrings.replyCount(post.replyCount);
    final DateTime? lastReplyAt = post.lastReplyAt;
    if (lastReplyAt == null) return count;
    final String time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(lastReplyAt));
    return '$count · ${ThreadStrings.lastReply(time)}';
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
