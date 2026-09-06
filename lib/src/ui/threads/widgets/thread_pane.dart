import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/repositories/emoji_repository.dart';
import 'package:mattermost_flutter/src/ui/messages/message_composer_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_attachments.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_composer.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_interaction_surface.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';
import 'package:mattermost_flutter/src/ui/threads/thread_controller.dart';
import 'package:mattermost_flutter/src/ui/threads/thread_strings.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

class ThreadPane extends ConsumerStatefulWidget {
  const ThreadPane({
    required this.rootPostId,
    required this.channel,
    required this.onClose,
    this.serverUrl,
    this.teamId,
    this.unreadReplies = 0,
    this.positionAtEndWhenRead = false,
    this.onSelectChannel,
    this.onReplySent,
    this.onThreadRead,
    this.onThreadUnfollowed,
    super.key,
  });

  final String rootPostId;
  final SidebarChannel channel;
  final VoidCallback onClose;
  final Uri? serverUrl;
  final String? teamId;
  final int unreadReplies;
  final bool positionAtEndWhenRead;
  final ValueChanged<String>? onSelectChannel;
  final ValueChanged<ChannelPost>? onReplySent;
  final ValueChanged<DateTime>? onThreadRead;
  final ValueChanged<String>? onThreadUnfollowed;

  @override
  ConsumerState<ThreadPane> createState() => _ThreadPaneState();
}

class _ThreadPaneState extends ConsumerState<ThreadPane> {
  late final ScrollController _scrollController = ScrollController();
  late final int _initialUnreadReplies = widget.unreadReplies;
  final GlobalKey _unreadDividerKey = GlobalKey();
  DateTime? _scheduledLoadedAt;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AuthSession? session = ref.watch(authSessionProvider);
    final AsyncValue<ThreadViewState> value = ref.watch(
      threadProvider(_request),
    );
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
                onRetry: () =>
                    ref.read(threadProvider(_request).notifier).retry(),
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
                        ref.read(threadProvider(_request).notifier).retry(),
                  );
                }
                _scheduleInitialPosition(state);
                final int unreadReplies =
                    _initialUnreadReplies < state.thread.replies.length
                    ? _initialUnreadReplies
                    : state.thread.replies.length;
                final int firstUnreadIndex =
                    state.thread.replies.length - unreadReplies;
                return Column(
                  children: <Widget>[
                    if (state.refreshFailed)
                      MaterialBanner(
                        content: const Text(ThreadStrings.loadFailed),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => ref
                                .read(threadProvider(_request).notifier)
                                .retry(),
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
                      child: ListView(
                        key: ValueKey<String>(
                          'thread-message-list-${widget.rootPostId}',
                        ),
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: <Widget>[
                          _ThreadPost(
                            post: root,
                            serverUrl: widget.serverUrl,
                            onSelectChannel: widget.onSelectChannel,
                            onToggleReaction: (PostReaction reaction) =>
                                _toggleReaction(root, reaction.emojiName),
                            onAddReaction: (String emojiName) =>
                                _toggleReaction(root, emojiName),
                            emojiRepositoryFactory: session == null
                                ? null
                                : () => ref.read(customEmojiRepositoryProvider),
                            accountId: session?.durableDataScopeId ?? '',
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
                                post: state.thread.replies[index],
                                serverUrl: widget.serverUrl,
                                onSelectChannel: widget.onSelectChannel,
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
                                emojiRepositoryFactory: session == null
                                    ? null
                                    : () => ref.read(
                                        customEmojiRepositoryProvider,
                                      ),
                                accountId: session?.durableDataScopeId ?? '',
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
                      placeholder: MessageComposerStrings.replyPlaceholder,
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

  void _scheduleInitialPosition(ThreadViewState state) {
    final DateTime? loadedAt = state.thread.loadedAt;
    if (!state.thread.isComplete ||
        loadedAt == null ||
        _scheduledLoadedAt == loadedAt) {
      return;
    }
    _scheduledLoadedAt = loadedAt;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
        .read(threadProvider(_request).notifier)
        .markRead(teamId: teamId);
    if (mounted && marked) widget.onThreadRead?.call(loadedAt);
  }

  Future<void> _sendReply(String message, String pendingPostId) async {
    final ChannelPost sent = await ref
        .read(threadProvider(_request).notifier)
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
        .read(threadProvider(_request).notifier)
        .toggleReaction(postId: post.id, emojiName: emojiName);
    if (!succeeded && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(ThreadStrings.reactionFailed)),
      );
    }
    return succeeded;
  }

  ThreadRequest get _request => (
    rootPostId: widget.rootPostId,
    teamId: widget.teamId ?? widget.channel.teamId,
    allowsFollowing: widget.channel.kind != ChannelKind.directMessage,
  );

  Future<void> _toggleFollowing() async {
    final bool wasFollowing =
        ref.read(threadProvider(_request)).asData?.value.isFollowing ?? false;
    final bool succeeded = await ref
        .read(threadProvider(_request).notifier)
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
    required this.serverUrl,
    required this.onSelectChannel,
    required this.onToggleReaction,
    required this.onAddReaction,
    required this.emojiRepositoryFactory,
    required this.accountId,
  });

  final ChannelPost post;
  final Uri? serverUrl;
  final ValueChanged<String>? onSelectChannel;
  final Future<void> Function(PostReaction reaction) onToggleReaction;
  final Future<bool> Function(String emojiName) onAddReaction;
  final CustomEmojiRepository Function()? emojiRepositoryFactory;
  final String accountId;

  @override
  Widget build(BuildContext context) {
    return MessageInteractionSurface(
      onOpenThread: null,
      onToggleReaction: onAddReaction,
      emojiRepositoryFactory: emojiRepositoryFactory,
      accountId: accountId,
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
                MessageBody(
                  post: post,
                  serverUrl: serverUrl,
                  onSelectChannel: onSelectChannel,
                  deletedMessage: ThreadStrings.deletedMessage,
                ),
                if (post.attachments.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  MessageAttachments(attachments: post.attachments),
                ],
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
