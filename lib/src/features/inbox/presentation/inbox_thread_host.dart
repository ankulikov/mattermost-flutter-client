import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_channel_route.dart';
import 'package:mattermost_flutter/src/ui/auth/auth_controller.dart';
import 'package:mattermost_flutter/src/ui/posts/widgets/channel_posts_pane.dart';
import 'package:mattermost_flutter/src/ui/threads/thread_route.dart';
import 'package:mattermost_flutter/src/ui/threads/widgets/thread_pane.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

typedef InboxPaneBuilder =
    Widget Function(BuildContext context, ValueChanged<InboxItem> onOpenItem);

/// The thread and channel context reached from an Inbox item.
final class InboxThreadTarget {
  const InboxThreadTarget({
    required this.rootPostId,
    required this.channel,
    required this.teamId,
    this.unreadReplies = 0,
    this.positionAtEndWhenRead = false,
  });

  /// Resolves thread-capable Inbox items to the root thread they open.
  ///
  /// A single direct message behaves like any other post and opens its thread.
  /// Multi-message bundles open their chat through [InboxThreadHost] and are
  /// deliberately rejected here.
  factory InboxThreadTarget.fromItem(InboxItem item) {
    return switch (item) {
      ThreadInboxItem(
        thread: final thread,
        channel: final channel,
        teamId: final teamId,
      ) =>
        InboxThreadTarget(
          rootPostId: thread.id,
          channel: channel,
          teamId: teamId,
          unreadReplies: thread.unreadReplies,
          positionAtEndWhenRead: thread.unreadReplies == 0,
        ),
      ChannelPostInboxItem(candidate: final candidate) => InboxThreadTarget(
        rootPostId: _rootPostId(candidate.post),
        channel: candidate.channel,
        teamId: candidate.channel.teamId,
      ),
      DirectMessageBundleInboxItem(messages: [final message]) =>
        InboxThreadTarget(
          rootPostId: _rootPostId(message.post),
          channel: message.channel,
          teamId: message.channel.teamId,
        ),
      DirectMessageBundleInboxItem() => throw ArgumentError.value(
        item,
        'item',
        'Multi-message bundles open their channel, not a thread',
      ),
    };
  }

  final String rootPostId;
  final SidebarChannel channel;
  final String teamId;
  final int unreadReplies;
  final bool positionAtEndWhenRead;

  static String _rootPostId(Post post) =>
      post.rootId.isEmpty ? post.id : post.rootId;
}

/// Hosts Inbox navigation without coupling Inbox rows to the app router.
///
/// When enough width is available, Inbox remains visible and the selected
/// thread or chat replaces only the adjacent workspace. On narrower layouts
/// the destination is pushed as a route, so platform Back returns to the
/// existing Inbox route and its state.
class InboxThreadHost extends ConsumerStatefulWidget {
  const InboxThreadHost({
    required this.inboxBuilder,
    required this.background,
    required this.showAdjacentWorkspace,
    this.onSelectChannel,
    this.onOpenPostLink,
    this.inboxWidth = 380,
    super.key,
  });

  final InboxPaneBuilder inboxBuilder;
  final Widget background;
  final bool showAdjacentWorkspace;
  final ValueChanged<String>? onSelectChannel;
  final ValueChanged<String>? onOpenPostLink;
  final double inboxWidth;

  @override
  ConsumerState<InboxThreadHost> createState() => _InboxThreadHostState();
}

class _InboxThreadHostState extends ConsumerState<InboxThreadHost> {
  InboxThreadTarget? _selectedTarget;
  SidebarChannel? _selectedChannel;

  @override
  Widget build(BuildContext context) {
    final Uri? serverUrl = ref.watch(
      authControllerProvider.select(
        (AuthState state) => state.session?.serverUrl,
      ),
    );
    final Widget inbox = widget.inboxBuilder(context, (InboxItem item) {
      if (item case DirectMessageBundleInboxItem(
        messages: final messages,
      ) when messages.length > 1) {
        final SidebarChannel channel = messages.last.channel;
        if (widget.showAdjacentWorkspace) {
          setState(() {
            _selectedTarget = null;
            _selectedChannel = channel;
          });
          return;
        }
        unawaited(
          InboxChannelRoute.open(
            context,
            InboxChannelRouteArguments(
              channel: channel,
              onSelectChannel: widget.onSelectChannel,
              onOpenPostLink: widget.onOpenPostLink,
            ),
          ),
        );
        return;
      }
      final InboxThreadTarget target = InboxThreadTarget.fromItem(item);
      if (widget.showAdjacentWorkspace) {
        setState(() {
          _selectedChannel = null;
          _selectedTarget = target;
        });
        return;
      }
      unawaited(_openThreadRoute(context, target, serverUrl));
    });

    if (!widget.showAdjacentWorkspace) {
      return KeyedSubtree(
        key: const ValueKey<String>('inbox-thread-host-narrow'),
        child: inbox,
      );
    }

    final InboxThreadTarget? target = _selectedTarget;
    final SidebarChannel? channel = _selectedChannel;
    return Row(
      key: const ValueKey<String>('inbox-thread-host-wide'),
      children: <Widget>[
        SizedBox(
          key: const ValueKey<String>('inbox-thread-list-pane'),
          width: widget.inboxWidth,
          child: inbox,
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: IndexedStack(
            index: channel != null
                ? 2
                : target != null
                ? 1
                : 0,
            children: <Widget>[
              widget.background,
              if (target == null)
                const SizedBox.shrink()
              else
                ThreadPane(
                  key: ValueKey<String>('inbox-thread-${target.rootPostId}'),
                  rootPostId: target.rootPostId,
                  channel: target.channel,
                  serverUrl: serverUrl,
                  teamId: target.teamId,
                  unreadReplies: target.unreadReplies,
                  positionAtEndWhenRead: target.positionAtEndWhenRead,
                  onSelectChannel: widget.onSelectChannel,
                  onOpenPostLink: widget.onOpenPostLink,
                  onThreadUnfollowed: _removeUnfollowedThread,
                  onClose: () => setState(() => _selectedTarget = null),
                ),
              if (channel == null)
                const SizedBox.shrink()
              else
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: ChannelPostsPane(
                    key: ValueKey<String>('inbox-channel-${channel.id}'),
                    channel: channel,
                    onSelectChannel: widget.onSelectChannel,
                    onOpenPostLink: widget.onOpenPostLink,
                    onBack: () => setState(() => _selectedChannel = null),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openThreadRoute(
    BuildContext context,
    InboxThreadTarget target,
    Uri? serverUrl,
  ) => ThreadRoute.open(
    context,
    ThreadRouteArguments(
      rootPostId: target.rootPostId,
      channel: target.channel,
      serverUrl: serverUrl,
      teamId: target.teamId,
      unreadReplies: target.unreadReplies,
      positionAtEndWhenRead: target.positionAtEndWhenRead,
      onSelectChannel: widget.onSelectChannel == null
          ? null
          : (String name) {
              widget.onSelectChannel!(name);
              if (context.mounted) Navigator.of(context).pop();
            },
      onThreadUnfollowed: _removeUnfollowedThread,
      onOpenPostLink: widget.onOpenPostLink == null
          ? null
          : (String postId) {
              if (context.mounted) Navigator.of(context).pop();
              widget.onOpenPostLink!(postId);
            },
    ),
  );

  void _removeUnfollowedThread(String rootPostId) {
    ref.read(inboxProvider.notifier).removeUnfollowedThread(rootPostId);
    if (mounted && _selectedTarget?.rootPostId == rootPostId) {
      setState(() => _selectedTarget = null);
    }
  }
}
