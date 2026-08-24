import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';
import 'package:mattermost_flutter/src/features/threads/presentation/thread_controller.dart';
import 'package:mattermost_flutter/src/features/threads/presentation/thread_strings.dart';

class ThreadPane extends ConsumerWidget {
  const ThreadPane({
    required this.rootPostId,
    required this.channel,
    required this.onClose,
    super.key,
  });

  final String rootPostId;
  final SidebarChannel channel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ThreadViewState> value = ref.watch(
      threadProvider(rootPostId),
    );
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ThreadHeader(channel: channel, onClose: onClose),
          const Divider(height: 1),
          Expanded(
            child: value.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _ThreadError(
                onRetry: () =>
                    ref.read(threadProvider(rootPostId).notifier).retry(),
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
                        ref.read(threadProvider(rootPostId).notifier).retry(),
                  );
                }
                return Column(
                  children: <Widget>[
                    if (state.refreshFailed)
                      MaterialBanner(
                        content: const Text(ThreadStrings.loadFailed),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => ref
                                .read(threadProvider(rootPostId).notifier)
                                .retry(),
                            child: const Text(ThreadStrings.retry),
                          ),
                        ],
                      ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: <Widget>[
                          _ThreadPost(post: root),
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
                          for (final ChannelPost reply in state.thread.replies)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _ThreadPost(post: reply),
                            ),
                        ],
                      ),
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
  const _ThreadPost({required this.post});

  final ChannelPost post;

  @override
  Widget build(BuildContext context) {
    final String time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(post.sentAt));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(child: Text(_initials(post.author.displayName))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 8,
                children: <Widget>[
                  Text(
                    post.author.displayName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(time, style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                post.isDeleted ? ThreadStrings.deletedMessage : post.message,
                style: post.isDeleted
                    ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();
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
