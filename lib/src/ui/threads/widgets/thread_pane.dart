import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/policies/post_permalink.dart';
import 'package:mattermost_flutter/src/domain/repositories/emoji_repository.dart';
import 'package:mattermost_flutter/src/ui/channels/channel_sidebar_controller.dart';
import 'package:mattermost_flutter/src/ui/messages/message_composer_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/post_action_navigation.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_composer.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_content.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_interaction_surface.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';
import 'package:mattermost_flutter/src/ui/posts/post_permalink_route.dart';
import 'package:mattermost_flutter/src/ui/threads/thread_controller.dart';
import 'package:mattermost_flutter/src/ui/threads/thread_strings.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

class ThreadPane extends ConsumerStatefulWidget {
  const ThreadPane({
    required this.rootPostId,
    required this.channel,
    required this.onClose,
    this.highlightedPostId,
    this.serverUrl,
    this.teamId,
    this.unreadReplies = 0,
    this.positionAtEndWhenRead = false,
    this.onSelectChannel,
    this.stateScopeId,
    this.onReplySent,
    this.onPostDeleted,
    this.onThreadRead,
    this.onThreadUnfollowed,
    super.key,
  });

  final String rootPostId;
  final SidebarChannel channel;
  final VoidCallback onClose;
  final String? highlightedPostId;
  final Uri? serverUrl;
  final String? teamId;
  final int unreadReplies;
  final bool positionAtEndWhenRead;
  final ValueChanged<String>? onSelectChannel;
  final String? stateScopeId;
  final ValueChanged<ChannelPost>? onReplySent;
  final ValueChanged<ChannelPost>? onPostDeleted;
  final ValueChanged<DateTime>? onThreadRead;
  final ValueChanged<String>? onThreadUnfollowed;

  @override
  ConsumerState<ThreadPane> createState() => _ThreadPaneState();
}

class _ThreadPaneState extends ConsumerState<ThreadPane> {
  late final ScrollController _scrollController = ScrollController();
  final MessageComposerController _composerController =
      MessageComposerController();
  late final int _initialUnreadReplies = widget.unreadReplies;
  final GlobalKey _unreadDividerKey = GlobalKey();
  final GlobalKey _highlightedPostKey = GlobalKey();
  GlobalKey _threadFocusCenterKey = GlobalKey();
  DateTime? _scheduledLoadedAt;
  String? _scheduledHighlightedPostId;

  AsyncNotifierProvider<ThreadController, ThreadViewState>
  get _threadStateProvider {
    final String? scopeId = widget.stateScopeId;
    return scopeId == null
        ? threadProvider(_request)
        : scopedThreadProvider((request: _request, scopeId: scopeId));
  }

  @override
  void didUpdateWidget(covariant ThreadPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightedPostId != widget.highlightedPostId) {
      _threadFocusCenterKey = GlobalKey();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Uri? _permalinkFor(String postId, {required String teamName}) {
    final Uri? serverUrl = widget.serverUrl;
    if (serverUrl == null) return null;
    return mattermostPostPermalink(
      serverUrl: serverUrl,
      teamName: teamName,
      postId: postId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AuthSession? session = ref.watch(authSessionProvider);
    final String sidebarTeamName = ref.watch(
      channelSidebarProvider.select(
        (AsyncValue<ChannelSidebarViewState> value) =>
            value.value?.snapshot.team?.name ?? '',
      ),
    );
    final String teamName = widget.channel.teamName.isNotEmpty
        ? widget.channel.teamName
        : sidebarTeamName;
    final AsyncValue<ThreadViewState> value = ref.watch(_threadStateProvider);
    final ThreadViewState? displayedState = value.asData?.value;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ThreadHeader(
            channel: widget.channel,
            onClose: widget.onClose,
            showsFollowButton: _request.allowsFollowing,
            isFollowing: displayedState?.isFollowing,
            isUpdatingFollow: displayedState?.isUpdatingFollow ?? false,
            onToggleFollowing: _toggleFollowing,
          ),
          const Divider(height: 1),
          Expanded(
            child: value.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _ThreadError(
                onRetry: () => ref.read(_threadStateProvider.notifier).retry(),
              ),
              data: (ThreadViewState state) {
                final ChannelPost? root = state.thread.root;
                if (root == null && state.isRefreshing) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (root == null) {
                  return _ThreadError(
                    message: ThreadStrings.missingRoot,
                    onRetry: () =>
                        ref.read(_threadStateProvider.notifier).retry(),
                  );
                }
                _scheduleInitialPosition(state);
                final int unreadReplies =
                    _initialUnreadReplies < state.thread.replies.length
                    ? _initialUnreadReplies
                    : state.thread.replies.length;
                final int firstUnreadIndex =
                    state.thread.replies.length - unreadReplies;
                final int? highlightedIndex =
                    switch (widget.highlightedPostId) {
                      final String id when id == root.id => 0,
                      final String id => () {
                        final int replyIndex = state.thread.replies.indexWhere(
                          (ChannelPost reply) => reply.id == id,
                        );
                        if (replyIndex < 0) return null;
                        return 2 +
                            replyIndex +
                            (unreadReplies > 0 && replyIndex >= firstUnreadIndex
                                ? 1
                                : 0);
                      }(),
                      null => null,
                    };
                return Column(
                  children: <Widget>[
                    if (state.refreshFailed)
                      MaterialBanner(
                        content: const Text(ThreadStrings.loadFailed),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () =>
                                ref.read(_threadStateProvider.notifier).retry(),
                            child: const Text(ThreadStrings.retry),
                          ),
                        ],
                      ),
                    if (state.markReadFailed)
                      MaterialBanner(
                        content: const Text(ThreadStrings.markReadFailed),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => unawaited(_markRead(state)),
                            child: const Text(ThreadStrings.retry),
                          ),
                        ],
                      ),
                    Expanded(
                      child: _buildThreadMessages(
                        highlightedIndex: highlightedIndex,
                        children: <Widget>[
                          _ThreadPost(
                            key: widget.highlightedPostId == root.id
                                ? _highlightedPostKey
                                : ValueKey<String>('thread-post-${root.id}'),
                            post: root,
                            highlighted: widget.highlightedPostId == root.id,
                            serverUrl: widget.serverUrl,
                            postPermalink: _permalinkFor(
                              root.id,
                              teamName: teamName,
                            ),
                            onSelectChannel: widget.onSelectChannel,
                            onQuoteSelection: _composerController.insertQuote,
                            onToggleReaction: (PostReaction reaction) =>
                                _toggleReaction(root, reaction.emojiName),
                            onAddReaction: (String emojiName) =>
                                _toggleReaction(root, emojiName),
                            onDelete: () => _deletePost(root),
                            canDelete: root.author.id == session?.userId,
                            canEdit: root.author.id == session?.userId,
                            emojiRepositoryFactory: session == null
                                ? null
                                : () => ref.read(customEmojiRepositoryProvider),
                            accountId: session?.durableDataScopeId ?? '',
                            actionScopeId:
                                widget.stateScopeId ?? widget.rootPostId,
                            onRichAttachmentPostUpdated: (ChannelPost post) =>
                                ref
                                    .read(_threadStateProvider.notifier)
                                    .replacePost(post),
                            onRichAttachmentGotoLocation: (String location) =>
                                unawaited(
                                  handlePostActionGotoLocation(
                                    context,
                                    serverUrl: widget.serverUrl,
                                    location: location,
                                  ),
                                ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: <Widget>[
                                Text(
                                  ThreadStrings.replyCount(
                                    state.thread.replies.length,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(child: Divider()),
                              ],
                            ),
                          ),
                          for (
                            var index = 0;
                            index < state.thread.replies.length;
                            index += 1
                          ) ...<Widget>[
                            if (unreadReplies > 0 && index == firstUnreadIndex)
                              _UnreadMessagesDivider(key: _unreadDividerKey),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _ThreadPost(
                                key:
                                    widget.highlightedPostId ==
                                        state.thread.replies[index].id
                                    ? _highlightedPostKey
                                    : ValueKey<String>(
                                        'thread-post-${state.thread.replies[index].id}',
                                      ),
                                post: state.thread.replies[index],
                                highlighted:
                                    widget.highlightedPostId ==
                                    state.thread.replies[index].id,
                                serverUrl: widget.serverUrl,
                                postPermalink: _permalinkFor(
                                  state.thread.replies[index].id,
                                  teamName: teamName,
                                ),
                                onSelectChannel: widget.onSelectChannel,
                                onQuoteSelection:
                                    _composerController.insertQuote,
                                onToggleReaction: (PostReaction reaction) =>
                                    _toggleReaction(
                                      state.thread.replies[index],
                                      reaction.emojiName,
                                    ),
                                onAddReaction: (String emojiName) =>
                                    _toggleReaction(
                                      state.thread.replies[index],
                                      emojiName,
                                    ),
                                onDelete: () =>
                                    _deletePost(state.thread.replies[index]),
                                canDelete:
                                    state.thread.replies[index].author.id ==
                                    session?.userId,
                                canEdit:
                                    state.thread.replies[index].author.id ==
                                    session?.userId,
                                emojiRepositoryFactory: session == null
                                    ? null
                                    : () => ref.read(
                                        customEmojiRepositoryProvider,
                                      ),
                                accountId: session?.durableDataScopeId ?? '',
                                actionScopeId:
                                    widget.stateScopeId ?? widget.rootPostId,
                                onRichAttachmentPostUpdated:
                                    (ChannelPost post) => ref
                                        .read(_threadStateProvider.notifier)
                                        .replacePost(post),
                                onRichAttachmentGotoLocation:
                                    (String location) => unawaited(
                                      handlePostActionGotoLocation(
                                        context,
                                        serverUrl: widget.serverUrl,
                                        location: location,
                                      ),
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (state.followUpdateFailed)
                      const MaterialBanner(
                        content: Text(ThreadStrings.followUpdateFailed),
                        actions: <Widget>[],
                      ),
                    MessageComposer(
                      key: ValueKey<String>(
                        'thread-composer-${widget.rootPostId}',
                      ),
                      destinationId: 'thread-${widget.rootPostId}',
                      composerController: _composerController,
                      placeholder: MessageComposerStrings.replyPlaceholder,
                      emojiRepositoryFactory: session == null
                          ? null
                          : () => ref.read(customEmojiRepositoryProvider),
                      mentionRepositoryFactory: session == null
                          ? null
                          : () => ref.read(mentionRepositoryProvider),
                      teamId: widget.teamId ?? widget.channel.teamId,
                      channelId: widget.channel.id,
                      accountId: session?.durableDataScopeId ?? '',
                      onSubmit: _sendReply,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThreadMessages({
    required List<Widget> children,
    required int? highlightedIndex,
  }) {
    final Key listKey = ValueKey<String>(
      'thread-message-list-${widget.rootPostId}',
    );
    if (highlightedIndex == null) {
      return ListView(
        key: listKey,
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: children,
      );
    }
    return CustomScrollView(
      key: listKey,
      controller: _scrollController,
      center: _threadFocusCenterKey,
      anchor: 0.35,
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              // Slivers before the center grow upward, so reverse their
              // builder order to preserve root -> divider -> replies visually.
              children
                  .sublist(0, highlightedIndex)
                  .reversed
                  .toList(growable: false),
            ),
          ),
        ),
        SliverPadding(
          key: _threadFocusCenterKey,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              children.sublist(highlightedIndex),
            ),
          ),
        ),
      ],
    );
  }

  void _scheduleInitialPosition(ThreadViewState state) {
    final DateTime? loadedAt = state.thread.loadedAt;
    if (!state.thread.isComplete ||
        loadedAt == null ||
        (_scheduledLoadedAt == loadedAt &&
            _scheduledHighlightedPostId == widget.highlightedPostId)) {
      return;
    }
    _scheduledLoadedAt = loadedAt;
    _scheduledHighlightedPostId = widget.highlightedPostId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.highlightedPostId != null) {
        final BuildContext? postContext = _highlightedPostKey.currentContext;
        if (postContext != null) {
          unawaited(
            Scrollable.ensureVisible(
              postContext,
              alignment: 0.35,
              duration: const Duration(milliseconds: 180),
            ),
          );
          return;
        }
      }
      if (_initialUnreadReplies > 0) {
        final BuildContext? dividerContext = _unreadDividerKey.currentContext;
        if (dividerContext != null) {
          unawaited(Scrollable.ensureVisible(dividerContext, alignment: 0));
        }
        if (_request.teamId.isNotEmpty) unawaited(_markRead(state));
        return;
      }
      if (widget.positionAtEndWhenRead && _scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _markRead(ThreadViewState state) async {
    final String teamId = _request.teamId;
    final DateTime? loadedAt = state.thread.loadedAt;
    if (teamId.isEmpty || loadedAt == null) return;
    final bool marked = await ref
        .read(_threadStateProvider.notifier)
        .markRead(teamId: teamId);
    if (mounted && marked) widget.onThreadRead?.call(loadedAt);
  }

  Future<void> _sendReply(String message, String pendingPostId) async {
    final ChannelPost sent = await ref
        .read(_threadStateProvider.notifier)
        .sendText(
          channelId: widget.channel.id,
          message: message,
          pendingPostId: pendingPostId,
        );
    widget.onReplySent?.call(sent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      unawaited(
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  Future<bool> _toggleReaction(ChannelPost post, String emojiName) async {
    final bool succeeded = await ref
        .read(_threadStateProvider.notifier)
        .toggleReaction(postId: post.id, emojiName: emojiName);
    if (!succeeded && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(ThreadStrings.reactionFailed)),
      );
    }
    return succeeded;
  }

  Future<bool> _deletePost(ChannelPost post) async {
    final bool deleted = await ref
        .read(_threadStateProvider.notifier)
        .deletePost(post.id);
    if (!deleted || !mounted) return false;
    widget.onPostDeleted?.call(post);
    if (post.id == widget.rootPostId) widget.onClose();
    return deleted;
  }

  ThreadRequest get _request => (
    rootPostId: widget.rootPostId,
    teamId: widget.teamId ?? widget.channel.teamId,
    allowsFollowing: widget.channel.kind != ChannelKind.directMessage,
  );

  Future<void> _toggleFollowing() async {
    final bool wasFollowing =
        ref.read(_threadStateProvider).asData?.value.isFollowing ?? false;
    final bool succeeded = await ref
        .read(_threadStateProvider.notifier)
        .toggleFollowing();
    if (!mounted) return;
    if (succeeded && wasFollowing) {
      widget.onThreadUnfollowed?.call(widget.rootPostId);
    } else if (!succeeded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(ThreadStrings.followUpdateFailed)),
      );
    }
  }
}

class _UnreadMessagesDivider extends StatelessWidget {
  const _UnreadMessagesDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: ThreadStrings.unreadMessages,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: <Widget>[
            Expanded(child: Divider(color: color)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                ThreadStrings.unreadMessages,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: color),
              ),
            ),
            Expanded(child: Divider(color: color)),
          ],
        ),
      ),
    );
  }
}

class _ThreadHeader extends StatelessWidget {
  const _ThreadHeader({
    required this.channel,
    required this.onClose,
    required this.showsFollowButton,
    required this.isFollowing,
    required this.isUpdatingFollow,
    required this.onToggleFollowing,
  });

  final SidebarChannel channel;
  final VoidCallback onClose;
  final bool showsFollowButton;
  final bool? isFollowing;
  final bool isUpdatingFollow;
  final Future<void> Function() onToggleFollowing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                ThreadStrings.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '#${channel.displayName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (showsFollowButton)
          TextButton(
            onPressed: isFollowing == null || isUpdatingFollow
                ? null
                : () => unawaited(onToggleFollowing()),
            child: isUpdatingFollow
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    isFollowing == true
                        ? ThreadStrings.following
                        : ThreadStrings.follow,
                  ),
          ),
        IconButton(
          tooltip: ThreadStrings.close,
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}

class _ThreadPost extends StatelessWidget {
  const _ThreadPost({
    required this.post,
    required this.highlighted,
    required this.serverUrl,
    required this.postPermalink,
    required this.onSelectChannel,
    required this.onQuoteSelection,
    required this.onToggleReaction,
    required this.onAddReaction,
    required this.onDelete,
    required this.canDelete,
    required this.canEdit,
    required this.emojiRepositoryFactory,
    required this.accountId,
    required this.actionScopeId,
    required this.onRichAttachmentPostUpdated,
    required this.onRichAttachmentGotoLocation,
    super.key,
  });

  final ChannelPost post;
  final bool highlighted;
  final Uri? serverUrl;
  final Uri? postPermalink;
  final ValueChanged<String>? onSelectChannel;
  final ValueChanged<String> onQuoteSelection;
  final Future<void> Function(PostReaction reaction) onToggleReaction;
  final Future<bool> Function(String emojiName) onAddReaction;
  final Future<bool> Function() onDelete;
  final bool canDelete;
  final bool canEdit;
  final CustomEmojiRepository Function()? emojiRepositoryFactory;
  final String accountId;
  final String actionScopeId;
  final ValueChanged<ChannelPost> onRichAttachmentPostUpdated;
  final ValueChanged<String> onRichAttachmentGotoLocation;

  @override
  Widget build(BuildContext context) {
    return MessageInteractionSurface(
      onOpenThread: null,
      touchBehavior: MessageTouchBehavior.actionsOnTap,
      onToggleReaction: onAddReaction,
      onDelete: onDelete,
      canDelete: canDelete,
      canEdit: canEdit,
      emojiRepositoryFactory: emojiRepositoryFactory,
      accountId: accountId,
      postPermalink: postPermalink,
      child: AnimatedContainer(
        key: highlighted
            ? ValueKey<String>('highlighted-thread-post-${post.id}')
            : null,
        duration: const Duration(milliseconds: 180),
        color: highlighted
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        child: Semantics(
          label: highlighted ? ThreadStrings.highlightedMessage : null,
          container: highlighted,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              MessageAvatar(author: post.author),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    MessageAuthorLine(author: post.author, sentAt: post.sentAt),
                    const SizedBox(height: 4),
                    MessageContent(
                      post: post,
                      serverUrl: serverUrl,
                      onSelectChannel: onSelectChannel,
                      onQuoteSelection: onQuoteSelection,
                      onOpenPostLink: (String postId) =>
                          unawaited(PostPermalinkRoute.push(context, postId)),
                      deletedMessage: ThreadStrings.deletedMessage,
                      onRichAttachmentAction: (_, _) {},
                      actionScopeId: actionScopeId,
                      onRichAttachmentPostUpdated: onRichAttachmentPostUpdated,
                      onRichAttachmentGotoLocation:
                          onRichAttachmentGotoLocation,
                    ),
                    if (post.reactions.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      MessageReactions(
                        post: post,
                        semanticsLabel: ThreadStrings.reactions,
                        onToggle: onToggleReaction,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadError extends StatelessWidget {
  const _ThreadError({
    required this.onRetry,
    this.message = ThreadStrings.loadFailed,
  });

  final VoidCallback onRetry;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text(ThreadStrings.retry),
          ),
        ],
      ),
    ),
  );
}
