import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/repositories/emoji_repository.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_breakpoints.dart';
import 'package:mattermost_flutter/src/ui/messages/message_composer_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_attachments.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_composer.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_interaction_surface.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';
import 'package:mattermost_flutter/src/ui/posts/channel_posts_controller.dart';
import 'package:mattermost_flutter/src/ui/posts/channel_posts_strings.dart';
import 'package:mattermost_flutter/src/ui/threads/thread_route.dart';
import 'package:mattermost_flutter/src/ui/threads/thread_strings.dart';
import 'package:mattermost_flutter/src/ui/threads/widgets/thread_pane.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

class ChannelPostsPane extends ConsumerStatefulWidget {
  const ChannelPostsPane({
    required this.channel,
    this.onSelectChannel,
    this.onBack,
    super.key,
  });

  final SidebarChannel channel;
  final ValueChanged<String>? onSelectChannel;
  final VoidCallback? onBack;

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
    final AuthSession? session = ref.watch(authSessionProvider);
    final Uri? serverUrl = session?.serverUrl;
    final AsyncValue<ChannelPostsViewState> posts = ref.watch(
      channelPostsProvider(channel.id),
    );
    final ChannelPostsViewState? viewState = posts.value;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool showSideThread =
            constraints.maxWidth >= AppBreakpoints.sideThread;
        final Widget channelPane = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ChannelHeader(
              channel: channel,
              isLoading: viewState?.isLoadingOlder == true,
              onBack: widget.onBack,
            ),
            const Divider(height: 1),
            Expanded(
              child: posts.when(
                loading: () => const _PostsLoading(),
                error: (Object error, StackTrace stackTrace) => _PostsError(
                  onRetry: () => ref
                      .read(channelPostsProvider(channel.id).notifier)
                      .retry(),
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
                    serverUrl: serverUrl,
                    posts: items,
                    isLoadingOlder: state.isLoadingOlder,
                    hasOlder: state.hasOlder,
                    autoLoadOlder: !state.loadFailed,
                    onLoadOlder: () => ref
                        .read(channelPostsProvider(channel.id).notifier)
                        .loadOlder(),
                    onOpenThread: (ChannelPost post) {
                      if (showSideThread) {
                        setState(() => _selectedRootPostId = post.id);
                        return;
                      }
                      unawaited(
                        _openThreadRoute(
                          context: context,
                          rootPostId: post.id,
                          channel: channel,
                          serverUrl: serverUrl,
                        ),
                      );
                    },
                    onToggleReaction: (ChannelPost post, String emojiName) =>
                        _toggleReaction(context, post, emojiName),
                    emojiRepositoryFactory: session == null
                        ? null
                        : () => ref.read(customEmojiRepositoryProvider),
                    accountId: session?.durableDataScopeId ?? '',
                    onSelectChannel: widget.onSelectChannel,
                  );
                },
              ),
            ),
            if (viewState != null)
              MessageComposer(
                key: ValueKey<String>('channel-composer-${channel.id}'),
                destinationId: channel.id,
                placeholder: MessageComposerStrings.channelPlaceholder(
                  channel.displayName,
                ),
                onSubmit: (String message, String pendingPostId) async {
                  await ref
                      .read(channelPostsProvider(channel.id).notifier)
                      .sendText(message: message, pendingPostId: pendingPostId);
                },
              ),
          ],
        );
        final String? rootPostId = _selectedRootPostId;
        if (rootPostId == null) return channelPane;
        final Widget thread = ThreadPane(
          key: ValueKey<String>('thread-$rootPostId'),
          rootPostId: rootPostId,
          channel: channel,
          serverUrl: serverUrl,
          teamId: channel.teamId,
          onSelectChannel: widget.onSelectChannel,
          onReplySent: (ChannelPost reply) => ref
              .read(channelPostsProvider(channel.id).notifier)
              .recordSentReply(reply),
          onClose: () => setState(() => _selectedRootPostId = null),
        );
        if (showSideThread) {
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

  Future<void> _openThreadRoute({
    required BuildContext context,
    required String rootPostId,
    required SidebarChannel channel,
    required Uri? serverUrl,
  }) => ThreadRoute.open(
    context,
    ThreadRouteArguments(
      rootPostId: rootPostId,
      channel: channel,
      serverUrl: serverUrl,
      teamId: channel.teamId,
      onSelectChannel: widget.onSelectChannel == null
          ? null
          : (String name) {
              widget.onSelectChannel!(name);
              if (context.mounted) context.pop();
            },
      onReplySent: (ChannelPost reply) => ref
          .read(channelPostsProvider(channel.id).notifier)
          .recordSentReply(reply),
    ),
  );

  Future<bool> _toggleReaction(
    BuildContext context,
    ChannelPost post,
    String emojiName,
  ) async {
    final bool succeeded = await ref
        .read(channelPostsProvider(widget.channel.id).notifier)
        .toggleReaction(postId: post.id, emojiName: emojiName);
    if (!succeeded && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(ChannelPostsStrings.reactionFailed)),
      );
    }
    return succeeded;
  }
}

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({
    required this.channel,
    required this.isLoading,
    required this.onBack,
  });

  final SidebarChannel channel;
  final bool isLoading;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    child: Row(
      children: <Widget>[
        if (onBack != null) ...<Widget>[
          BackButton(onPressed: onBack),
          const SizedBox(width: 4),
        ],
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
    required this.serverUrl,
    required this.posts,
    required this.isLoadingOlder,
    required this.hasOlder,
    required this.autoLoadOlder,
    required this.onLoadOlder,
    required this.onOpenThread,
    required this.onToggleReaction,
    required this.emojiRepositoryFactory,
    required this.accountId,
    required this.onSelectChannel,
  });

  final String channelId;
  final Uri? serverUrl;
  final List<ChannelPost> posts;
  final bool isLoadingOlder;
  final bool hasOlder;
  final bool autoLoadOlder;
  final Future<void> Function() onLoadOlder;
  final ValueChanged<ChannelPost> onOpenThread;
  final Future<bool> Function(ChannelPost, String) onToggleReaction;
  final CustomEmojiRepository Function()? emojiRepositoryFactory;
  final String accountId;
  final ValueChanged<String>? onSelectChannel;

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
            serverUrl: widget.serverUrl,
            continuesAuthor: continuesAuthor,
            onOpenThread: widget.onOpenThread,
            onToggleReaction: widget.onToggleReaction,
            emojiRepositoryFactory: widget.emojiRepositoryFactory,
            accountId: widget.accountId,
            onSelectChannel: widget.onSelectChannel,
          );
        },
      ),
    );
  }
}

class _PostRow extends StatelessWidget {
  const _PostRow({
    required this.post,
    required this.serverUrl,
    required this.continuesAuthor,
    required this.onOpenThread,
    required this.onToggleReaction,
    required this.emojiRepositoryFactory,
    required this.accountId,
    required this.onSelectChannel,
    super.key,
  });

  final ChannelPost post;
  final Uri? serverUrl;
  final bool continuesAuthor;
  final ValueChanged<ChannelPost> onOpenThread;
  final Future<bool> Function(ChannelPost, String) onToggleReaction;
  final CustomEmojiRepository Function()? emojiRepositoryFactory;
  final String accountId;
  final ValueChanged<String>? onSelectChannel;

  @override
  Widget build(BuildContext context) {
    return MessageInteractionSurface(
      onOpenThread: () => onOpenThread(post),
      onToggleReaction: (String emojiName) => onToggleReaction(post, emojiName),
      emojiRepositoryFactory: emojiRepositoryFactory,
      accountId: accountId,
      child: Padding(
        padding: EdgeInsets.only(
          top: continuesAuthor ? 2 : 8,
          bottom: continuesAuthor ? 2 : 4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (continuesAuthor)
              const SizedBox(width: 44)
            else
              MessageAvatar(author: post.author),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (!continuesAuthor) ...<Widget>[
                    MessageAuthorLine(author: post.author, sentAt: post.sentAt),
                    const SizedBox(height: 5),
                  ],
                  MessageBody(
                    post: post,
                    serverUrl: serverUrl,
                    onSelectChannel: onSelectChannel,
                  ),
                  if (post.attachments.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    MessageAttachments(attachments: post.attachments),
                  ],
                  if (post.reactions.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    MessageReactions(
                      post: post,
                      semanticsLabel: ChannelPostsStrings.reactions,
                      onToggle: (PostReaction reaction) =>
                          onToggleReaction(post, reaction.emojiName),
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
