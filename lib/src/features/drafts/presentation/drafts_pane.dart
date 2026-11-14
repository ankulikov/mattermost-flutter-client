import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft.dart';
import 'package:mattermost_flutter/src/features/drafts/presentation/draft_focus.dart';
import 'package:mattermost_flutter/src/features/drafts/presentation/draft_send_controller.dart';
import 'package:mattermost_flutter/src/features/drafts/presentation/drafts_controller.dart';
import 'package:mattermost_flutter/src/features/drafts/presentation/drafts_strings.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_breakpoints.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_spacing.dart';
import 'package:mattermost_flutter/src/ui/core/widgets/avatar_initials.dart';
import 'package:mattermost_flutter/src/ui/core/widgets/relative_time.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';
import 'package:mattermost_flutter/src/ui/threads/widgets/thread_pane.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';
import 'package:mattermost_flutter/src/ui/users/widgets/user_avatar_image.dart';

class DraftsPane extends ConsumerStatefulWidget {
  const DraftsPane({
    required this.team,
    required this.channelsById,
    required this.onSelectChannel,
    this.onBack,
    super.key,
  });
  final SidebarTeam team;
  final Map<String, SidebarChannel> channelsById;
  final ValueChanged<String> onSelectChannel;
  final VoidCallback? onBack;

  @override
  ConsumerState<DraftsPane> createState() => _DraftsPaneState();
}

class _DraftsPaneState extends ConsumerState<DraftsPane> {
  Draft? _selected;
  bool _focusSelected = false;
  late DateTime _now;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    unawaited(
      Future<void>(
        () => ref
            .read(draftsControllerProvider.notifier)
            .loadTeam(widget.team.id),
      ),
    );
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  void _open(Draft draft) {
    if (draft.rootId == null || draft.rootId!.isEmpty) {
      final channel = widget.channelsById[draft.channelId];
      if (channel != null) {
        ref.read(draftFocusRequestProvider.notifier).request(channel.id);
        widget.onSelectChannel(channel.name);
      }
    } else {
      setState(() {
        _selected = draft;
        _focusSelected = true;
      });
    }
  }

  Future<void> _confirmDelete(DraftKey key, String destination) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text(DraftsStrings.deleteTitle)),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.of(context).pop(false),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: Text(DraftsStrings.deleteConfirmation(destination)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(DraftsStrings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(DraftsStrings.confirmDelete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(draftsControllerProvider.notifier).delete(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(draftsControllerProvider);
    final sends = ref.watch(draftSendControllerProvider);
    final teamKeys = state.teamKeys[widget.team.id] ?? const <DraftKey>{};
    final entries =
        state.entries.entries
            .where(
              (entry) =>
                  teamKeys.contains(entry.key) ||
                  widget.channelsById.containsKey(entry.key.channelId),
            )
            .toList()
          ..sort(
            (a, b) => b.value.draft.updateAt.compareTo(a.value.draft.updateAt),
          );
    final serverUrl = ref.watch(
      authControllerProvider.select((state) => state.session?.serverUrl),
    );
    final list = Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            widget.onBack == null ? 20 : 4,
            14,
            20,
            12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.onBack case final VoidCallback onBack) ...[
                BackButton(onPressed: onBack),
                const SizedBox(width: 4),
              ],
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DraftsStrings.title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(DraftsStrings.subtitle),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (state.syncStatus == DraftSyncStatus.disabled ||
            state.syncStatus == DraftSyncStatus.unsupported)
          const MaterialBanner(
            content: Text(DraftsStrings.syncUnavailable),
            actions: [SizedBox.shrink()],
          ),
        if (state.error != null &&
            entries.isNotEmpty &&
            state.syncStatus != DraftSyncStatus.unsupported)
          const MaterialBanner(
            content: Text(DraftsStrings.refreshFailed),
            actions: [SizedBox.shrink()],
          ),
        Expanded(
          child: state.loading && entries.isEmpty
              ? Center(
                  child: Semantics(
                    label: DraftsStrings.loading,
                    child: const CircularProgressIndicator(),
                  ),
                )
              : state.error != null && entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(DraftsStrings.loadFailed),
                      TextButton(
                        onPressed: () => unawaited(
                          ref
                              .read(draftsControllerProvider.notifier)
                              .loadTeam(widget.team.id, refresh: true),
                        ),
                        child: const Text(DraftsStrings.retry),
                      ),
                    ],
                  ),
                )
              : entries.isEmpty
              ? const Center(child: Text(DraftsStrings.empty))
              : LayoutBuilder(
                  builder: (context, constraints) => ListView.builder(
                    padding: EdgeInsets.symmetric(
                      horizontal: constraints.maxWidth >= AppBreakpoints.compact
                          ? AppLayout.expandedPageGutter
                          : AppLayout.compactPageGutter,
                      vertical: AppSpacing.md,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final key = entries[index].key;
                      final entry = entries[index].value;
                      final draft = entry.draft;
                      final sendStatus = sends[key];
                      final channel = widget.channelsById[draft.channelId];
                      final title = channel == null
                          ? draft.channelId
                          : (channel.displayName.trim().isEmpty
                                ? channel.name
                                : channel.displayName);
                      final theme = Theme.of(context);
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AppLayout.readableContentWidth,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Card(
                              margin: EdgeInsets.zero,
                              elevation: 0,
                              surfaceTintColor: Colors.transparent,
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  InkWell(
                                    onTap: channel == null
                                        ? null
                                        : () => _open(draft),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _DraftAvatar(
                                            channel: channel,
                                            title: title,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .baseline,
                                                  textBaseline:
                                                      TextBaseline.alphabetic,
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        draft.rootId?.isNotEmpty ==
                                                                true
                                                            ? '$title · ${DraftsStrings.thread}'
                                                            : title,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: theme
                                                            .textTheme
                                                            .labelLarge,
                                                      ),
                                                    ),
                                                    if (draft.updateAt > 0) ...[
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        formatFollowedThreadLastReplyTime(
                                                          lastReplyAt:
                                                              DateTime.fromMillisecondsSinceEpoch(
                                                                draft.updateAt,
                                                              ),
                                                          now: _now,
                                                          localizations:
                                                              MaterialLocalizations.of(
                                                                context,
                                                              ),
                                                        ),
                                                        style: theme
                                                            .textTheme
                                                            .labelMedium
                                                            ?.copyWith(
                                                              color: theme
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                            ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                MessageMarkdown(
                                                  data: draft.message,
                                                  serverUrl: serverUrl,
                                                ),
                                                if (draft.fileIds.isNotEmpty)
                                                  Text(
                                                    DraftsStrings.attachments(
                                                      draft.fileIds.length,
                                                    ),
                                                  ),
                                                if (sendStatus?.phase ==
                                                    DraftSendPhase.failed)
                                                  const Text(
                                                    DraftsStrings.sendFailed,
                                                  ),
                                                if (sendStatus?.phase ==
                                                    DraftSendPhase
                                                        .cleanupPending)
                                                  const Text(
                                                    DraftsStrings
                                                        .cleanupPending,
                                                  ),
                                                if (sendStatus?.phase ==
                                                    DraftSendPhase.unsupported)
                                                  const Text(
                                                    DraftsStrings
                                                        .unsupportedOptions,
                                                  ),
                                                if (entry.error != null)
                                                  const Text(
                                                    DraftsStrings.syncFailed,
                                                  ),
                                                if (entry.dirty &&
                                                    draft.message.isEmpty)
                                                  const Text(
                                                    DraftsStrings.unsynced,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Divider(
                                    height: 1,
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    child: OverflowBar(
                                      alignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                theme.colorScheme.error,
                                          ),
                                          onPressed: () => unawaited(
                                            _confirmDelete(key, title),
                                          ),
                                          label: const Text(
                                            DraftsStrings.delete,
                                          ),
                                        ),
                                        TextButton.icon(
                                          icon: const Icon(Icons.send_outlined),
                                          onPressed:
                                              sendStatus?.phase ==
                                                  DraftSendPhase.sending
                                              ? null
                                              : () => unawaited(
                                                  ref
                                                      .read(
                                                        draftSendControllerProvider
                                                            .notifier,
                                                      )
                                                      .send(key),
                                                ),
                                          label: Text(
                                            sendStatus?.phase ==
                                                    DraftSendPhase
                                                        .cleanupPending
                                                ? DraftsStrings.retry
                                                : DraftsStrings.send,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
    final selected = _selected;
    if (selected == null) return list;
    final channel = widget.channelsById[selected.channelId];
    if (channel == null) return list;
    final thread = ThreadPane(
      rootPostId: selected.rootId!,
      autofocusComposer: _focusSelected,
      channel: channel,
      teamId: widget.team.id,
      serverUrl: serverUrl,
      onSelectChannel: widget.onSelectChannel,
      onClose: () => setState(() => _selected = null),
    );
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >= AppBreakpoints.sideThread
          ? Row(
              children: [
                Expanded(child: list),
                const VerticalDivider(width: 1),
                SizedBox(width: 420, child: thread),
              ],
            )
          : thread,
    );
  }
}

class _DraftAvatar extends StatelessWidget {
  const _DraftAvatar({required this.channel, required this.title});

  final SidebarChannel? channel;
  final String title;

  @override
  Widget build(BuildContext context) {
    final profile = channel?.profileImage;
    if (channel?.kind == ChannelKind.directMessage && profile != null) {
      return UserAvatarImage(
        userId: profile.userId,
        displayName: title,
        profileImageUpdatedAt: profile.updatedAt,
        radius: 22,
      );
    }
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: 22,
        backgroundColor: avatarColor(title),
        foregroundColor: Colors.white,
        child: Text(avatarInitials(title)),
      ),
    );
  }
}
