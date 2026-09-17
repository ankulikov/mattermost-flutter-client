import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/post_navigation.dart';
import 'package:mattermost_flutter/src/domain/repositories/emoji_repository.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_breakpoints.dart';
import 'package:mattermost_flutter/src/ui/messages/message_composer_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_attachments.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_composer.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_interaction_surface.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';
import 'package:mattermost_flutter/src/ui/posts/channel_posts_controller.dart';
import 'package:mattermost_flutter/src/ui/posts/channel_posts_strings.dart';
import 'package:mattermost_flutter/src/ui/posts/post_permalink_route.dart';
import 'package:mattermost_flutter/src/ui/threads/thread_route.dart';
import 'package:mattermost_flutter/src/ui/threads/thread_strings.dart';
import 'package:mattermost_flutter/src/ui/threads/widgets/thread_pane.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

class ChannelPostsPane extends ConsumerStatefulWidget {
  const ChannelPostsPane({
    required this.channel,
    this.onSelectChannel,
    this.navigationTarget,
    this.stateScopeId,
    this.onBack,
    super.key,
  });

  final SidebarChannel channel;
  final ValueChanged<String>? onSelectChannel;
  final PostNavigationTarget? navigationTarget;
  final String? stateScopeId;
  final VoidCallback? onBack;

  @override
  ConsumerState<ChannelPostsPane> createState() => _ChannelPostsPaneState();
}

class _ChannelPostsPaneState extends ConsumerState<ChannelPostsPane> {
  String? _selectedRootPostId;
  String? _highlightedThreadPostId;
  PostNavigationTarget? _scheduledFocusTarget;
  PostNavigationTarget? _openedThreadTarget;

  AsyncNotifierProvider<ChannelPostsController, ChannelPostsViewState>
  get _postsProvider {
    final String? scopeId = widget.stateScopeId;
    return scopeId == null
        ? channelPostsProvider(widget.channel.id)
        : scopedChannelPostsProvider((
            channelId: widget.channel.id,
            scopeId: scopeId,
          ));
  }

  @override
  void didUpdateWidget(covariant ChannelPostsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) {
      _selectedRootPostId = null;
      _highlightedThreadPostId = null;
    }
    if (!identical(oldWidget.navigationTarget, widget.navigationTarget)) {
      _openedThreadTarget = null;
      _selectedRootPostId = null;
      _highlightedThreadPostId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final SidebarChannel channel = widget.channel;
    final AuthSession? session = ref.watch(authSessionProvider);
    final Uri? serverUrl = session?.serverUrl;
    final AsyncValue<ChannelPostsViewState> posts = ref.watch(_postsProvider);
    final ChannelPostsViewState? viewState = posts.value;
    _scheduleFocus(widget.navigationTarget);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool showSideThread =
            constraints.maxWidth >= AppBreakpoints.sideThread;
        _scheduleTargetThread(
          target: widget.navigationTarget,
          state: viewState,
          showSideThread: showSideThread,
          serverUrl: serverUrl,
        );
        final Widget channelPane = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ChannelHeader(
              channel: channel,
              isLoading:
                  viewState?.isLoadingOlder == true ||
                  viewState?.isLoadingNewer == true ||
                  viewState?.isFocusing == true,
              onBack: widget.onBack,
            ),
            const Divider(height: 1),
            if (viewState?.focusFailed == true)
              MaterialBanner(
                content: const Text(
                  ChannelPostsStrings.linkedMessageLoadFailed,
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () =>
                        ref.read(_postsProvider.notifier).retryFocus(),
                    child: const Text(ChannelPostsStrings.retry),
                  ),
                ],
              ),
            Expanded(
              child: posts.when(
                loading: () => const _PostsLoading(),
                error: (Object error, StackTrace stackTrace) => _PostsError(
                  onRetry: () => ref.read(_postsProvider.notifier).retry(),
                ),
                data: (ChannelPostsViewState state) {
                  final List<ChannelPost> items = state.posts;
                  if (items.isEmpty && state.loadFailed) {
                    return _PostsError(
                      onRetry: () => ref.read(_postsProvider.notifier).retry(),
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
                    isLoadingNewer: state.isLoadingNewer,
                    hasOlder: state.hasOlder,
                    hasNewer: state.hasNewer,
                    focusedPostId: state.focusPostId,
                    autoLoadOlder: !state.loadFailed && !state.isFocusing,
                    onLoadOlder: () =>
                        ref.read(_postsProvider.notifier).loadOlder(),
                    onLoadNewer: () =>
                        ref.read(_postsProvider.notifier).loadNewer(),
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
                emojiRepositoryFactory: session == null
                    ? null
                    : () => ref.read(customEmojiRepositoryProvider),
                mentionRepositoryFactory: session == null
                    ? null
                    : () => ref.read(mentionRepositoryProvider),
                teamId: channel.teamId,
                channelId: channel.id,
                accountId: session?.durableDataScopeId ?? '',
                onSubmit: (String message, String pendingPostId) async {
                  await ref
                      .read(_postsProvider.notifier)
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
          highlightedPostId: _highlightedThreadPostId,
          channel: channel,
          serverUrl: serverUrl,
          teamId: channel.teamId,
          onSelectChannel: widget.onSelectChannel,
          stateScopeId: widget.stateScopeId,
          onReplySent: (ChannelPost reply) =>
              ref.read(_postsProvider.notifier).recordSentReply(reply),
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

  void _scheduleFocus(PostNavigationTarget? target) {
    if (target == null ||
        target.channel.id != widget.channel.id ||
        identical(_scheduledFocusTarget, target)) {
      return;
    }
    _scheduledFocusTarget = target;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !identical(widget.navigationTarget, target)) return;
      try {
        await ref.read(_postsProvider.future);
      } on Object {
        // The controller retains the session and can replace an initial error
        // with the historical window on the focus request below.
      }
      if (!mounted || !identical(widget.navigationTarget, target)) return;
      await ref.read(_postsProvider.notifier).focusOn(target.channelPostId);
    });
  }

  void _scheduleTargetThread({
    required PostNavigationTarget? target,
    required ChannelPostsViewState? state,
    required bool showSideThread,
    required Uri? serverUrl,
  }) {
    if (target == null ||
        target.threadRootPostId == null ||
        state?.focusPostId != target.channelPostId ||
        identical(_openedThreadTarget, target)) {
      return;
    }
    _openedThreadTarget = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(widget.navigationTarget, target)) return;
      if (showSideThread) {
        setState(() {
          _selectedRootPostId = target.threadRootPostId;
          _highlightedThreadPostId = target.threadHighlightedPostId;
        });
        return;
      }
      unawaited(
        _openThreadRoute(
          context: context,
          rootPostId: target.threadRootPostId!,
          highlightedPostId: target.threadHighlightedPostId,
          channel: widget.channel,
          serverUrl: serverUrl,
        ),
      );
    });
  }

  Future<void> _openThreadRoute({
    required BuildContext context,
    required String rootPostId,
    String? highlightedPostId,
    required SidebarChannel channel,
    required Uri? serverUrl,
  }) => ThreadRoute.open(
    context,
    ThreadRouteArguments(
      rootPostId: rootPostId,
      highlightedPostId: highlightedPostId,
      channel: channel,
      serverUrl: serverUrl,
      teamId: channel.teamId,
      onSelectChannel: widget.onSelectChannel == null
          ? null
          : (String name) {
              widget.onSelectChannel!(name);
              if (context.mounted) context.pop();
            },
      onReplySent: (ChannelPost reply) =>
          ref.read(_postsProvider.notifier).recordSentReply(reply),
    ),
  );

  Future<bool> _toggleReaction(
    BuildContext context,
    ChannelPost post,
    String emojiName,
  ) async {
    final bool succeeded = await ref
        .read(_postsProvider.notifier)
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
    required this.isLoadingNewer,
    required this.hasOlder,
    required this.hasNewer,
    required this.focusedPostId,
    required this.autoLoadOlder,
    required this.onLoadOlder,
    required this.onLoadNewer,
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
  final bool isLoadingNewer;
  final bool hasOlder;
  final bool hasNewer;
  final String? focusedPostId;
  final bool autoLoadOlder;
  final Future<void> Function() onLoadOlder;
  final Future<void> Function() onLoadNewer;
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
  bool _newerLoadPending = false;
  bool _viewportCheckScheduled = false;
  int _automaticLoadCount = 0;
  GlobalKey _focusCenterKey = GlobalKey();

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
    if (oldWidget.channelId != widget.channelId ||
        (oldWidget.isLoadingNewer && !widget.isLoadingNewer)) {
      _newerLoadPending = false;
    }
    if (oldWidget.focusedPostId != widget.focusedPostId) {
      _focusCenterKey = GlobalKey();
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
    if (!_controller.hasClients) return;
    if (widget.focusedPostId != null) {
      if (_controller.position.extentBefore < 160) _requestOlder();
      if (_controller.position.extentAfter < 160) _requestNewer();
      return;
    }
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

  void _requestNewer() {
    if (_newerLoadPending || widget.isLoadingNewer || !widget.hasNewer) return;
    _newerLoadPending = true;
    unawaited(
      widget.onLoadNewer().whenComplete(() {
        if (!mounted) return;
        _newerLoadPending = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? focusedPostId = widget.focusedPostId;
    final int focusIndex = focusedPostId == null
        ? -1
        : widget.posts.indexWhere(
            (ChannelPost post) => post.id == focusedPostId,
          );
    if (focusIndex >= 0) return _buildFocusedList(focusIndex);
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
          return _buildPostRow(postIndex);
        },
      ),
    );
  }

  Widget _buildFocusedList(int focusIndex) => CustomScrollView(
    key: PageStorageKey<String>(
      'channel-posts-${widget.channelId}-${widget.focusedPostId}',
    ),
    controller: _controller,
    center: _focusCenterKey,
    anchor: 0.35,
    slivers: <Widget>[
      if (widget.isLoadingOlder)
        _loadingSliver(ChannelPostsStrings.loadingOlder),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          // Slivers before the center grow upward, so their builder order must
          // run backward to keep the visual timeline chronological.
          (BuildContext context, int index) =>
              _buildPostRow(focusIndex - 1 - index),
          childCount: focusIndex,
        ),
      ),
      SliverList(
        key: _focusCenterKey,
        delegate: SliverChildBuilderDelegate(
          (BuildContext context, int index) =>
              _buildPostRow(focusIndex + index),
          childCount: widget.posts.length - focusIndex,
        ),
      ),
      if (widget.isLoadingNewer) _loadingSliver(ChannelPostsStrings.loading),
    ],
  );

  Widget _loadingSliver(String label) => SliverToBoxAdapter(
    child: Semantics(
      label: label,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    ),
  );

  Widget _buildPostRow(int postIndex) {
    final ChannelPost post = widget.posts[postIndex];
    final bool continuesAuthor =
        postIndex > 0 &&
        widget.posts[postIndex - 1].author.id == post.author.id;
    return _PostRow(
      key: ValueKey<String>(post.id),
      post: post,
      serverUrl: widget.serverUrl,
      continuesAuthor: continuesAuthor,
      highlighted: post.id == widget.focusedPostId,
      onOpenThread: widget.onOpenThread,
      onToggleReaction: widget.onToggleReaction,
      emojiRepositoryFactory: widget.emojiRepositoryFactory,
      accountId: widget.accountId,
      onSelectChannel: widget.onSelectChannel,
    );
  }
}

class _PostRow extends StatelessWidget {
  const _PostRow({
    required this.post,
    required this.serverUrl,
    required this.continuesAuthor,
    required this.highlighted,
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
  final bool highlighted;
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
      child: AnimatedContainer(
        key: highlighted
            ? ValueKey<String>('highlighted-post-${post.id}')
            : null,
        duration: const Duration(milliseconds: 180),
        color: highlighted
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        child: Semantics(
          label: highlighted ? ChannelPostsStrings.highlightedMessage : null,
          container: highlighted,
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
                        MessageAuthorLine(
                          author: post.author,
                          sentAt: post.sentAt,
                        ),
                        const SizedBox(height: 5),
                      ],
                      MessageBody(
                        post: post,
                        serverUrl: serverUrl,
                        onSelectChannel: onSelectChannel,
                        onOpenPostLink: (String postId) =>
                            unawaited(PostPermalinkRoute.push(context, postId)),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
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
