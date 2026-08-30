import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/app/di/app_providers.dart';
import 'package:mattermost_flutter/src/features/attachments/presentation/message_attachments.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message.dart';
import 'package:mattermost_flutter/src/features/messages/presentation/message_composer.dart';
import 'package:mattermost_flutter/src/features/messages/presentation/message_composer_strings.dart';
import 'package:mattermost_flutter/src/features/messages/presentation/message_primitives.dart';
import 'package:mattermost_flutter/src/features/threads/presentation/thread_controller.dart';
import 'package:mattermost_flutter/src/features/threads/presentation/thread_strings.dart';

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
    final AsyncValue<ThreadViewState> value = ref.watch(
      threadProvider(widget.rootPostId),
    );
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ThreadHeader(channel: widget.channel, onClose: widget.onClose),
          const Divider(height: 1),
          Expanded(
            child: value.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _ThreadError(
                onRetry: () => ref
                    .read(threadProvider(widget.rootPostId).notifier)
                    .retry(),
              ),
              data: (ThreadViewState state) {
                final ChannelPost? root = state.thread.root;
                if (root == null && state.isRefreshing) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (root == null) {
                  return _ThreadError(
                    message: ThreadStrings.missingRoot,
                    onRetry: () => ref
                        .read(threadProvider(widget.rootPostId).notifier)
                        .retry(),
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
                                .read(
                                  threadProvider(widget.rootPostId).notifier,
                                )
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
                                _toggleReaction(root, reaction),
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
                                      reaction,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
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
        if (widget.teamId != null) unawaited(_markRead(state));
        return;
      }
      if (widget.positionAtEndWhenRead && _scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _markRead(ThreadViewState state) async {
    final String? teamId = widget.teamId;
    final DateTime? loadedAt = state.thread.loadedAt;
    if (teamId == null || loadedAt == null) return;
    final bool marked = await ref
        .read(threadProvider(widget.rootPostId).notifier)
        .markRead(teamId: teamId);
    if (mounted && marked) widget.onThreadRead?.call(loadedAt);
  }

  Future<void> _sendReply(String message, String pendingPostId) async {
    final ChannelPost sent = await ref
        .read(threadProvider(widget.rootPostId).notifier)
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

  Future<void> _toggleReaction(ChannelPost post, PostReaction reaction) async {
    final bool succeeded = await ref
        .read(threadProvider(widget.rootPostId).notifier)
        .toggleReaction(postId: post.id, emojiName: reaction.emojiName);
    if (!succeeded && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(ThreadStrings.reactionFailed)),
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
  const _ThreadHeader({required this.channel, required this.onClose});

  final SidebarChannel channel;
  final VoidCallback onClose;

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
  });

  final ChannelPost post;
  final Uri? serverUrl;
  final ValueChanged<String>? onSelectChannel;
  final Future<void> Function(PostReaction reaction) onToggleReaction;

  @override
  Widget build(BuildContext context) {
    return Row(
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
