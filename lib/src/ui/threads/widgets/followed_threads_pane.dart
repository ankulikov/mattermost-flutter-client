import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/ui/auth/auth_controller.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_breakpoints.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_preview_card.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';
import 'package:mattermost_flutter/src/ui/threads/followed_threads_controller.dart';
import 'package:mattermost_flutter/src/ui/threads/followed_threads_strings.dart';
import 'package:mattermost_flutter/src/ui/threads/thread_route.dart';
import 'package:mattermost_flutter/src/ui/threads/widgets/thread_pane.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

class FollowedThreadsPane extends ConsumerStatefulWidget {
  const FollowedThreadsPane({
    required this.team,
    required this.channelsById,
    this.onSelectChannel,
    this.onBack,
    super.key,
  });

  final SidebarTeam team;
  final Map<String, SidebarChannel> channelsById;
  final ValueChanged<String>? onSelectChannel;
  final VoidCallback? onBack;

  @override
  ConsumerState<FollowedThreadsPane> createState() =>
      _FollowedThreadsPaneState();
}

class _FollowedThreadsPaneState extends ConsumerState<FollowedThreadsPane> {
  String? _selectedThreadId;

  @override
  void didUpdateWidget(covariant FollowedThreadsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.team.id != widget.team.id) _selectedThreadId = null;
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<FollowedThreadsViewState> value = ref.watch(
      followedThreadsProvider(widget.team.id),
    );
    final Uri? serverUrl = ref.watch(
      authControllerProvider.select(
        (AuthState state) => state.session?.serverUrl,
      ),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool showSideThread =
            constraints.maxWidth >= AppBreakpoints.sideThread;
        final Widget listPane = Column(
          key: const ValueKey<String>('followed-threads-list-pane'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ThreadsHeader(onBack: widget.onBack),
            const Divider(height: 1),
            Expanded(
              child: value.when(
                loading: () => const _Loading(),
                error: (_, _) => _Error(
                  onRetry: () =>
                      ref.invalidate(followedThreadsProvider(widget.team.id)),
                ),
                data: (FollowedThreadsViewState state) => _ThreadsBody(
                  teamId: widget.team.id,
                  state: state,
                  selectedThreadId: _selectedThreadId,
                  channelsById: widget.channelsById,
                  serverUrl: serverUrl,
                  onSelect: (FollowedThread thread) {
                    if (showSideThread) {
                      setState(() => _selectedThreadId = thread.id);
                      return;
                    }
                    unawaited(_openThreadRoute(context, thread, serverUrl));
                  },
                ),
              ),
            ),
          ],
        );
        final FollowedThread? selected = value.value?.items
            .where((FollowedThread item) => item.id == _selectedThreadId)
            .firstOrNull;
        if (selected == null) return listPane;
        final SidebarChannel channel =
            widget.channelsById[selected.channelId] ??
            SidebarChannel(
              id: selected.channelId,
              teamId: widget.team.id,
              name: selected.channelId,
              displayName: selected.channelId,
              kind: ChannelKind.publicChannel,
            );
        final Widget threadPane = ThreadPane(
          key: ValueKey<String>('followed-thread-${selected.id}'),
          rootPostId: selected.id,
          channel: channel,
          serverUrl: serverUrl,
          teamId: widget.team.id,
          unreadReplies: selected.unreadReplies,
          positionAtEndWhenRead: true,
          onSelectChannel: widget.onSelectChannel,
          onThreadRead: (DateTime timestamp) => ref
              .read(followedThreadsProvider(widget.team.id).notifier)
              .recordThreadRead(rootPostId: selected.id, timestamp: timestamp),
          onThreadUnfollowed: (String rootPostId) => ref
              .read(followedThreadsProvider(widget.team.id).notifier)
              .removeUnfollowedThread(rootPostId),
          onClose: () => setState(() => _selectedThreadId = null),
        );
        if (showSideThread) {
          return Row(
            children: <Widget>[
              Expanded(child: listPane),
              const VerticalDivider(width: 1),
              SizedBox(width: 420, child: threadPane),
            ],
          );
        }
        return Stack(
          children: <Widget>[
            Positioned.fill(child: listPane),
            Positioned.fill(child: threadPane),
          ],
        );
      },
    );
  }

  Future<void> _openThreadRoute(
    BuildContext context,
    FollowedThread thread,
    Uri? serverUrl,
  ) {
    final SidebarChannel channel =
        widget.channelsById[thread.channelId] ??
        SidebarChannel(
          id: thread.channelId,
          teamId: widget.team.id,
          name: thread.channelId,
          displayName: thread.channelId,
          kind: ChannelKind.publicChannel,
        );
    return ThreadRoute.open(
      context,
      ThreadRouteArguments(
        rootPostId: thread.id,
        channel: channel,
        serverUrl: serverUrl,
        teamId: widget.team.id,
        unreadReplies: thread.unreadReplies,
        positionAtEndWhenRead: true,
        onSelectChannel: widget.onSelectChannel == null
            ? null
            : (String name) {
                widget.onSelectChannel!(name);
                if (context.mounted) context.pop();
              },
        onThreadRead: (DateTime timestamp) => ref
            .read(followedThreadsProvider(widget.team.id).notifier)
            .recordThreadRead(rootPostId: thread.id, timestamp: timestamp),
        onThreadUnfollowed: (String rootPostId) => ref
            .read(followedThreadsProvider(widget.team.id).notifier)
            .removeUnfollowedThread(rootPostId),
      ),
    );
  }
}

class _ThreadsHeader extends StatelessWidget {
  const _ThreadsHeader({this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(onBack == null ? 20 : 4, 14, 20, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (onBack case final VoidCallback onBack) ...<Widget>[
          BackButton(onPressed: onBack),
          const SizedBox(width: 4),
        ],
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                FollowedThreadsStrings.title,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 2),
              Text(FollowedThreadsStrings.subtitle),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ThreadsBody extends ConsumerWidget {
  const _ThreadsBody({
    required this.teamId,
    required this.state,
    required this.selectedThreadId,
    required this.channelsById,
    required this.serverUrl,
    required this.onSelect,
  });

  final String teamId;
  final FollowedThreadsViewState state;
  final String? selectedThreadId;
  final Map<String, SidebarChannel> channelsById;
  final Uri? serverUrl;
  final ValueChanged<FollowedThread> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.items.isEmpty && !state.hasMore) {
      return RefreshIndicator(
        onRefresh: () =>
            ref.read(followedThreadsProvider(teamId).notifier).refresh(),
        child: ListView(
          children: const <Widget>[
            SizedBox(height: 160),
            Center(child: Text(FollowedThreadsStrings.empty)),
          ],
        ),
      );
    }
    if (state.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () =>
            ref.read(followedThreadsProvider(teamId).notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            const SizedBox(height: 120),
            _LoadMore(
              loading: state.paginationStatus is OperationInProgress,
              failed: state.paginationStatus is OperationFailed,
              onPressed: () =>
                  ref.read(followedThreadsProvider(teamId).notifier).loadMore(),
            ),
          ],
        ),
      );
    }
    return Column(
      children: <Widget>[
        if (state.refreshStatus is OperationInProgress)
          const LinearProgressIndicator(minHeight: 2),
        if (state.refreshStatus is OperationFailed)
          MaterialBanner(
            content: const Text(FollowedThreadsStrings.refreshFailed),
            actions: <Widget>[
              TextButton(
                onPressed: () => ref
                    .read(followedThreadsProvider(teamId).notifier)
                    .refresh(),
                child: const Text(FollowedThreadsStrings.retry),
              ),
            ],
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () =>
                ref.read(followedThreadsProvider(teamId).notifier).refresh(),
            child: ListView.builder(
              key: PageStorageKey<String>('followed-threads-$teamId'),
              itemCount: state.items.length + (state.hasMore ? 1 : 0),
              itemBuilder: (BuildContext context, int index) {
                if (index == state.items.length) {
                  return _LoadMore(
                    loading: state.paginationStatus is OperationInProgress,
                    failed: state.paginationStatus is OperationFailed,
                    onPressed: () => ref
                        .read(followedThreadsProvider(teamId).notifier)
                        .loadMore(),
                  );
                }
                final FollowedThread thread = state.items[index];
                return Padding(
                  key: ValueKey<String>('followed-thread-tile-${thread.id}'),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: _ThreadCard(
                    thread: thread,
                    channelName:
                        channelsById[thread.channelId]?.displayName ??
                        thread.channelId,
                    serverUrl: serverUrl,
                    selected: thread.id == selectedThreadId,
                    onTap: () => onSelect(thread),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ThreadCard extends StatelessWidget {
  const _ThreadCard({
    required this.thread,
    required this.channelName,
    required this.serverUrl,
    required this.selected,
    required this.onTap,
  });

  final FollowedThread thread;
  final String channelName;
  final Uri? serverUrl;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _semanticLabel(),
      child: MessagePreviewCard(
        interactionKey: ValueKey<String>('followed-thread-card-${thread.id}'),
        header: channelName,
        post: thread.root,
        serverUrl: serverUrl,
        selected: selected,
        onTap: onTap,
        details: _ThreadSummary(thread: thread),
      ),
    );
  }

  String _semanticLabel() {
    if (thread.unreadMentions > 0) {
      return FollowedThreadsStrings.mentions(thread.unreadMentions);
    }
    if (thread.unreadReplies > 0) {
      return FollowedThreadsStrings.unreadReplies(thread.unreadReplies);
    }
    return FollowedThreadsStrings.replies(thread.replyCount);
  }
}

class _ThreadSummary extends StatelessWidget {
  const _ThreadSummary({required this.thread});

  final FollowedThread thread;

  static const double _avatarHitTarget = 44;
  static const double _avatarRadius = 12;
  static const double _avatarOverlap = 4;

  List<PostAuthor> get _visibleParticipants => thread.participants.length > 4
      ? thread.participants.take(3).toList(growable: false)
      : thread.participants.take(4).toList(growable: false);

  List<PostAuthor> get _remainingParticipants => thread.participants.length > 4
      ? thread.participants.skip(3).toList(growable: false)
      : const <PostAuthor>[];

  double get _participantStripWidth =>
      _avatarHitTarget +
      (_visibleParticipants.length +
              (_remainingParticipants.isEmpty ? 0 : 1) -
              1) *
          (_avatarRadius * 2 - _avatarOverlap);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<PostAuthor> participants = _visibleParticipants;
    final List<PostAuthor> remainingParticipants = _remainingParticipants;
    return Padding(
      key: ValueKey<String>('thread-participant-summary-${thread.id}'),
      // MessageAvatar reserves a 44 px accessible target, while the visible
      // avatar is 24 px wide. Offset the summary so its visible avatars align
      // with the root message body rather than the card edge.
      padding: const EdgeInsetsDirectional.fromSTEB(62, 10, 16, 10),
      child: Row(
        children: <Widget>[
          if (participants.isNotEmpty)
            SizedBox(
              width: _participantStripWidth,
              height: _avatarHitTarget,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  for (int index = 0; index < participants.length; index += 1)
                    PositionedDirectional(
                      start: index * (_avatarRadius * 2 - _avatarOverlap),
                      child: MessageAvatar(
                        author: participants[index],
                        radius: _avatarRadius,
                      ),
                    ),
                  if (remainingParticipants.isNotEmpty)
                    PositionedDirectional(
                      start:
                          participants.length *
                          (_avatarRadius * 2 - _avatarOverlap),
                      child: _RemainingParticipantsCounter(
                        threadId: thread.id,
                        participants: remainingParticipants,
                      ),
                    ),
                ],
              ),
            ),
          if (participants.isNotEmpty) const SizedBox(width: 8),
          Expanded(
            child: Text(
              FollowedThreadsStrings.replies(thread.replyCount),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          _UnreadIndicator(thread: thread),
        ],
      ),
    );
  }
}

class _RemainingParticipantsCounter extends StatelessWidget {
  const _RemainingParticipantsCounter({
    required this.threadId,
    required this.participants,
  });

  final String threadId;
  final List<PostAuthor> participants;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final String names = _tooltipNames(participants);
    return Tooltip(
      message: names,
      child: Semantics(
        label: FollowedThreadsStrings.additionalParticipants(
          participants.length,
        ),
        child: SizedBox.square(
          dimension: _ThreadSummary._avatarHitTarget,
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            child: Center(
              child: DecoratedBox(
                key: ValueKey<String>(
                  'thread-additional-participants-$threadId',
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: _ThreadSummary._avatarRadius * 2,
                  child: Center(
                    child: Text(
                      '+${participants.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _tooltipNames(List<PostAuthor> participants) {
    final List<String> rows = <String>[];
    for (int index = 0; index < participants.length; index += 2) {
      rows.add(
        participants
            .skip(index)
            .take(2)
            .map((PostAuthor participant) => participant.displayName)
            .join(', '),
      );
    }
    return rows.join('\n');
  }
}

class _UnreadIndicator extends StatelessWidget {
  const _UnreadIndicator({required this.thread});

  final FollowedThread thread;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    if (thread.unreadReplies > 0) {
      return Container(
        key: ValueKey<String>('thread-unread-count-${thread.id}'),
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '${thread.unreadReplies}',
          style: TextStyle(
            color: colors.onPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return const SizedBox(width: 8, height: 8);
  }
}

class _LoadMore extends StatelessWidget {
  const _LoadMore({
    required this.loading,
    required this.failed,
    required this.onPressed,
  });

  final bool loading;
  final bool failed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Center(
      child: loading
          ? Semantics(
              label: FollowedThreadsStrings.loadingMore,
              child: const CircularProgressIndicator(),
            )
          : OutlinedButton(
              onPressed: onPressed,
              child: Text(
                failed
                    ? FollowedThreadsStrings.retry
                    : FollowedThreadsStrings.loadMore,
              ),
            ),
    ),
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      label: FollowedThreadsStrings.loading,
      child: const CircularProgressIndicator(),
    ),
  );
}

class _Error extends StatelessWidget {
  const _Error({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(FollowedThreadsStrings.loadFailed),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onRetry,
          child: const Text(FollowedThreadsStrings.retry),
        ),
      ],
    ),
  );
}
