import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mattermost_flutter/src/domain/models/post_navigation.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_breakpoints.dart';
import 'package:mattermost_flutter/src/ui/posts/widgets/channel_posts_pane.dart';
import 'package:mattermost_flutter/src/ui/threads/widgets/thread_pane.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

/// Displays a resolved Mattermost post permalink without mutating shell state.
///
/// The page is a single navigation-stack entry. On wide constraints the target
/// channel stays visible and [ChannelPostsPane] opens its thread beside it. On
/// compact constraints a thread-capable target mounts [ThreadPane] directly,
/// so a Back action always removes this page instead of revealing an
/// intermediate channel screen.
class LinkedPostPage extends ConsumerWidget {
  const LinkedPostPage({
    required this.target,
    this.stateScopeId,
    this.onClose,
    super.key,
  });

  final PostNavigationTarget target;
  final String? stateScopeId;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Uri? serverUrl = ref.watch(
      authSessionProvider.select((session) => session?.serverUrl),
    );
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool showSideThread =
                constraints.maxWidth >= AppBreakpoints.sideThread;
            if (!showSideThread && target.threadRootPostId != null) {
              return _CompactLinkedThread(
                target: target,
                serverUrl: serverUrl,
                stateScopeId: stateScopeId ?? target.linkedPostId,
                onClose: onClose ?? context.pop,
              );
            }
            return ChannelPostsPane(
              key: ValueKey<String>(
                'linked-post-channel-${target.linkedPostId}',
              ),
              channel: target.channel,
              navigationTarget: target,
              stateScopeId: stateScopeId ?? target.linkedPostId,
              onBack: onClose ?? context.pop,
            );
          },
        ),
      ),
    );
  }
}

class _CompactLinkedThread extends StatelessWidget {
  const _CompactLinkedThread({
    required this.target,
    required this.serverUrl,
    required this.stateScopeId,
    required this.onClose,
  });

  final PostNavigationTarget target;
  final Uri? serverUrl;
  final String stateScopeId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.escape): onClose,
    },
    child: Focus(
      autofocus: true,
      child: ThreadPane(
        key: ValueKey<String>('linked-post-thread-${target.threadRootPostId}'),
        rootPostId: target.threadRootPostId!,
        highlightedPostId: target.threadHighlightedPostId,
        channel: target.channel,
        serverUrl: serverUrl,
        teamId: target.channel.teamId,
        stateScopeId: stateScopeId,
        onClose: onClose,
      ),
    ),
  );
}
