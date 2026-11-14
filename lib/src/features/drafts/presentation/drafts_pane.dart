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
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';
import 'package:mattermost_flutter/src/ui/threads/widgets/thread_pane.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

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

  @override
  void initState() {
    super.initState();
    unawaited(
      Future<void>(
        () => ref
            .read(draftsControllerProvider.notifier)
            .loadTeam(widget.team.id),
      ),
    );
  }

  void _open(Draft draft, {bool focus = false}) {
    if (draft.rootId == null || draft.rootId!.isEmpty) {
      final channel = widget.channelsById[draft.channelId];
      if (channel != null) {
        if (focus) {
          ref.read(draftFocusRequestProvider.notifier).request(channel.id);
        }
        widget.onSelectChannel(channel.name);
      }
    } else {
      setState(() {
        _selected = draft;
        _focusSelected = focus;
      });
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
        ListTile(
          leading: widget.onBack == null
              ? null
              : BackButton(onPressed: widget.onBack),
          title: const Text(DraftsStrings.title),
          trailing: IconButton(
            tooltip: DraftsStrings.refresh,
            onPressed: () => unawaited(
              ref
                  .read(draftsControllerProvider.notifier)
                  .loadTeam(widget.team.id, refresh: true),
            ),
            icon: const Icon(Icons.refresh),
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
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final key = entries[index].key;
                    final entry = entries[index].value;
                    final draft = entry.draft;
                    final sendStatus = sends[key];
                    final channel = widget.channelsById[draft.channelId];
                    final title = channel?.displayName ?? draft.channelId;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            onTap: channel == null ? null : () => _open(draft),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    draft.rootId?.isNotEmpty == true
                                        ? '$title · ${DraftsStrings.thread}'
                                        : title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  if (draft.updateAt > 0)
                                    Text(
                                      MaterialLocalizations.of(
                                        context,
                                      ).formatShortDate(
                                        DateTime.fromMillisecondsSinceEpoch(
                                          draft.updateAt,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  MessageMarkdown(
                                    data: draft.message,
                                    serverUrl: serverUrl,
                                  ),
                                  if (draft.fileIds.isNotEmpty)
                                    Text(
                                      '${draft.fileIds.length} attachment(s)',
                                    ),
                                  if (sendStatus?.phase ==
                                      DraftSendPhase.failed)
                                    const Text(DraftsStrings.sendFailed),
                                  if (sendStatus?.phase ==
                                      DraftSendPhase.cleanupPending)
                                    const Text(DraftsStrings.cleanupPending),
                                  if (sendStatus?.phase ==
                                      DraftSendPhase.unsupported)
                                    const Text(
                                      DraftsStrings.unsupportedOptions,
                                    ),
                                  if (entry.error != null)
                                    const Text(DraftsStrings.syncFailed),
                                  if (entry.dirty && draft.message.isEmpty)
                                    const Text(DraftsStrings.unsynced),
                                ],
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          OverflowBar(
                            alignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: channel == null
                                    ? null
                                    : () => _open(draft, focus: true),
                                child: const Text(DraftsStrings.edit),
                              ),
                              TextButton(
                                onPressed: () => unawaited(
                                  ref
                                      .read(draftsControllerProvider.notifier)
                                      .delete(key),
                                ),
                                child: const Text(DraftsStrings.delete),
                              ),
                              TextButton(
                                onPressed:
                                    sendStatus?.phase == DraftSendPhase.sending
                                    ? null
                                    : () => unawaited(
                                        ref
                                            .read(
                                              draftSendControllerProvider
                                                  .notifier,
                                            )
                                            .send(key),
                                      ),
                                child: Text(
                                  sendStatus?.phase ==
                                          DraftSendPhase.cleanupPending
                                      ? DraftsStrings.retry
                                      : DraftsStrings.send,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
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
