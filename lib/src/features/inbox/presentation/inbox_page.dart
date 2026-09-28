import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_completeness.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/classify_inbox_section.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_controller.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_page_controller.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_settings_page.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_strings.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

class InboxPage extends ConsumerStatefulWidget {
  const InboxPage({required this.onOpenItem, super.key});

  final ValueChanged<InboxItem> onOpenItem;

  @override
  ConsumerState<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends ConsumerState<InboxPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final ScrollController _newItemsScrollController;
  late final ScrollController _postponedScrollController;

  @override
  void initState() {
    super.initState();
    final InboxPageViewState pageState = ref.read(inboxPageProvider);
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: pageState.selectedTab.index,
    )..addListener(_saveSelectedTab);
    _newItemsScrollController = ScrollController(
      initialScrollOffset: pageState.newItemsScrollOffset,
    )..addListener(_saveNewItemsScrollOffset);
    _postponedScrollController = ScrollController(
      initialScrollOffset: pageState.postponedScrollOffset,
    )..addListener(_savePostponedScrollOffset);
  }

  @override
  void dispose() {
    _tabs.removeListener(_saveSelectedTab);
    _tabs.dispose();
    _newItemsScrollController
      ..removeListener(_saveNewItemsScrollOffset)
      ..dispose();
    _postponedScrollController
      ..removeListener(_savePostponedScrollOffset)
      ..dispose();
    super.dispose();
  }

  void _saveSelectedTab() {
    if (_tabs.indexIsChanging) return;
    ref
        .read(inboxPageProvider.notifier)
        .selectTab(InboxPageTab.values[_tabs.index]);
  }

  void _saveNewItemsScrollOffset() => ref
      .read(inboxPageProvider.notifier)
      .saveScrollOffset(
        InboxPageTab.newItems,
        _newItemsScrollController.offset,
      );

  void _savePostponedScrollOffset() => ref
      .read(inboxPageProvider.notifier)
      .saveScrollOffset(
        InboxPageTab.postponed,
        _postponedScrollController.offset,
      );

  @override
  Widget build(BuildContext context) {
    final AsyncValue<InboxSessionViewState> value = ref.watch(
      inboxSessionProvider,
    );
    final InboxPageViewState pageState = ref.watch(inboxPageProvider);
    return FocusTraversalGroup(
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(InboxStrings.title),
              const SizedBox(width: 10),
              _ConnectionIndicator(
                status:
                    value.value?.connectionStatus ??
                    InboxConnectionStatus.disconnected,
              ),
            ],
          ),
          actions: <Widget>[
            _InboxIconAction(
              label: InboxStrings.openSettings,
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        const InboxSettingsPage(),
                  ),
                );
              },
              icon: Icons.settings,
            ),
            _InboxIconAction(
              label: InboxStrings.refresh,
              onPressed: () =>
                  unawaited(ref.read(inboxSessionProvider.notifier).refresh()),
              icon: Icons.refresh,
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            tabs: <Widget>[
              _InboxTab(
                label: InboxStrings.newItems,
                count: value.value?.snapshot.newMessageCount ?? 0,
                countKey: const ValueKey<String>('inbox-new-count'),
              ),
              _InboxTab(
                label: InboxStrings.postponed,
                count: value.value?.snapshot.postponedMessageCount ?? 0,
                countKey: const ValueKey<String>('inbox-postponed-count'),
              ),
            ],
          ),
        ),
        body: value.when(
          loading: () => Semantics(
            label: InboxStrings.loading,
            child: const Center(child: CircularProgressIndicator()),
          ),
          error: (Object error, StackTrace stackTrace) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(InboxStrings.loadFailed),
                const SizedBox(height: 12),
                _InboxTextAction(
                  label: InboxStrings.retry,
                  semanticsLabel: InboxStrings.retryInbox,
                  onPressed: () => ref
                      .read(inboxSessionProvider.notifier)
                      .retryInitialLoad(),
                  outlined: true,
                ),
              ],
            ),
          ),
          data: (InboxSessionViewState state) => Column(
            children: <Widget>[
              if (state.refreshStatus is OperationInProgress)
                const LinearProgressIndicator(minHeight: 2),
              _InboxSnapshotStatus(
                snapshot: state.snapshot,
                refreshFailed: state.refreshStatus is OperationFailed,
                onRetryFull: () => unawaited(
                  ref.read(inboxSessionProvider.notifier).refresh(),
                ),
                onRetrySource: (InboxSourceScope scope) => unawaited(
                  ref.read(inboxSessionProvider.notifier).retrySource(scope),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: <Widget>[
                    _InboxList(
                      items: state.snapshot.newItems,
                      empty: InboxStrings.emptyNew,
                      onOpenItem: widget.onOpenItem,
                      isPostponed: false,
                      controller: _newItemsScrollController,
                      actionInProgress:
                          pageState.actionStatus is OperationInProgress,
                    ),
                    _InboxList(
                      items: state.snapshot.postponedItems,
                      empty: InboxStrings.emptyPostponed,
                      onOpenItem: widget.onOpenItem,
                      isPostponed: true,
                      controller: _postponedScrollController,
                      actionInProgress:
                          pageState.actionStatus is OperationInProgress,
                    ),
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

/// Content-free network coverage and source failure status for a useful Inbox
/// projection. It stays above both tabs so a failed source remains visible
/// even when its queue is not selected.
class _InboxSnapshotStatus extends StatelessWidget {
  const _InboxSnapshotStatus({
    required this.snapshot,
    required this.refreshFailed,
    required this.onRetryFull,
    required this.onRetrySource,
  });

  final InboxSnapshot snapshot;
  final bool refreshFailed;
  final VoidCallback onRetryFull;
  final ValueChanged<InboxSourceScope> onRetrySource;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      _InboxStatusMessage(
        key: ValueKey<String>(
          'inbox-completeness-${snapshot.completeness.name}',
        ),
        text: InboxStrings.completeness(snapshot.completeness),
        icon: switch (snapshot.completeness) {
          InboxCompleteness.exact => Icons.verified_outlined,
          InboxCompleteness.approximateMentions => Icons.info_outline,
          InboxCompleteness.truncated => Icons.warning_amber_outlined,
        },
        severity: switch (snapshot.completeness) {
          InboxCompleteness.exact => _InboxStatusSeverity.information,
          InboxCompleteness.approximateMentions => _InboxStatusSeverity.warning,
          InboxCompleteness.truncated => _InboxStatusSeverity.warning,
        },
      ),
      if (refreshFailed)
        _InboxStatusMessage(
          key: const ValueKey<String>('inbox-refresh-failure'),
          text: InboxStrings.refreshFailed,
          icon: Icons.cloud_off_outlined,
          severity: _InboxStatusSeverity.error,
          actionLabel: InboxStrings.retry,
          actionSemanticsLabel: InboxStrings.retryInbox,
          onAction: onRetryFull,
        ),
      for (final InboxSourceFailure failure in snapshot.sourceFailures)
        _InboxStatusMessage(
          key: ValueKey<String>('inbox-source-failure-${failure.scope.name}'),
          text: InboxStrings.sourceFailure(failure.scope),
          icon: Icons.error_outline,
          severity: _InboxStatusSeverity.error,
          actionLabel: InboxStrings.retry,
          actionSemanticsLabel: InboxStrings.retrySource(failure.scope),
          onAction: () => onRetrySource(failure.scope),
        ),
    ],
  );
}

enum _InboxStatusSeverity { information, warning, error }

class _InboxStatusMessage extends StatelessWidget {
  const _InboxStatusMessage({
    required this.text,
    required this.icon,
    required this.severity,
    super.key,
    this.actionLabel,
    this.actionSemanticsLabel,
    this.onAction,
  });

  final String text;
  final IconData icon;
  final _InboxStatusSeverity severity;
  final String? actionLabel;
  final String? actionSemanticsLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final (Color background, Color foreground) = switch (severity) {
      _InboxStatusSeverity.information => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      _InboxStatusSeverity.warning => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
      ),
      _InboxStatusSeverity.error => (
        colors.errorContainer,
        colors.onErrorContainer,
      ),
    };
    final Widget message = ExcludeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: foreground)),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      liveRegion: severity != _InboxStatusSeverity.information,
      label: text,
      child: Material(
        color: background,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget? action = actionLabel == null || onAction == null
                  ? null
                  : _InboxTextAction(
                      label: actionLabel!,
                      semanticsLabel: actionSemanticsLabel ?? actionLabel!,
                      onPressed: onAction,
                    );
              if (action == null) return message;
              if (constraints.maxWidth < 460) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    message,
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: action,
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(child: message),
                  action,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _InboxTab extends StatelessWidget {
  const _InboxTab({
    required this.label,
    required this.count,
    required this.countKey,
  });

  final String label;
  final int count;
  final Key countKey;

  @override
  Widget build(BuildContext context) => Semantics(
    label: InboxStrings.tabWithMessageCount(label, count),
    child: Tab(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label),
            const SizedBox(width: 8),
            Badge(
              label: Text('$count', key: countKey),
              child: const SizedBox(width: 20, height: 20),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ConnectionIndicator extends StatelessWidget {
  const _ConnectionIndicator({required this.status});

  final InboxConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final bool connected = status == InboxConnectionStatus.connected;
    final String label = switch (status) {
      InboxConnectionStatus.connecting => InboxStrings.connecting,
      InboxConnectionStatus.connected => InboxStrings.connected,
      InboxConnectionStatus.disconnected => InboxStrings.disconnected,
    };
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        key: const ValueKey<String>('inbox-connection-indicator'),
        label: label,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: connected ? Colors.green : Colors.red,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _InboxList extends StatelessWidget {
  const _InboxList({
    required this.items,
    required this.empty,
    required this.onOpenItem,
    required this.isPostponed,
    required this.controller,
    required this.actionInProgress,
  });

  final List<InboxItem> items;
  final String empty;
  final ValueChanged<InboxItem> onOpenItem;
  final bool isPostponed;
  final ScrollController controller;
  final bool actionInProgress;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Semantics(liveRegion: true, child: Text(empty)));
    }
    final Map<InboxSection, List<InboxItem>> sections =
        <InboxSection, List<InboxItem>>{
          for (final InboxSection section in InboxSection.values)
            section: <InboxItem>[],
        };
    final Iterable<InboxItem> presentationItems = isPostponed
        ? items.expand(_postponedPresentationItems)
        : items;
    for (final InboxItem item in presentationItems) {
      sections[classifyInboxSection(item)]!.add(item);
    }
    return ListView(
      controller: controller,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: <Widget>[
        for (final InboxSection section in InboxSection.values)
          if (sections[section]!.isNotEmpty) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: _InboxSectionHeader(
                section: section,
                label: _sectionLabel(section),
                messageCount: _messageCount(sections[section]!),
              ),
            ),
            for (final InboxItem item in sections[section]!)
              _InboxRow(
                item: item,
                onOpen: () => onOpenItem(item),
                isPostponed: isPostponed,
                actionInProgress: actionInProgress,
              ),
          ],
      ],
    );
  }

  Iterable<InboxItem> _postponedPresentationItems(InboxItem item) sync* {
    if (item case DirectMessageBundleInboxItem(:final messages)) {
      for (final message in messages) {
        yield DirectMessageBundleInboxItem(
          channelId: item.channelId,
          authorId: item.authorId,
          automationClass: item.automationClass,
          messages: <InboxPostCandidate>[message],
          postponedAt: item.postponedAt,
        );
      }
      return;
    }
    yield item;
  }

  String _sectionLabel(InboxSection section) => switch (section) {
    InboxSection.mentions => InboxStrings.mentions,
    InboxSection.allActivity => InboxStrings.allActivity,
    InboxSection.botsAndIntegrations => InboxStrings.bots,
    InboxSection.directMessages => InboxStrings.directMessages,
    InboxSection.threads => InboxStrings.threads,
  };

  int _messageCount(Iterable<InboxItem> items) => items.fold<int>(
    0,
    (int count, InboxItem item) => count + item.postIds.length,
  );
}

class _InboxSectionHeader extends StatelessWidget {
  const _InboxSectionHeader({
    required this.section,
    required this.label,
    required this.messageCount,
  });

  final InboxSection section;
  final String label;
  final int messageCount;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    label: InboxStrings.sectionWithMessageCount(label, messageCount),
    child: ExcludeSemantics(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.titleSmall),
          ),
          Text(
            InboxStrings.messages(messageCount),
            key: ValueKey<String>('inbox-section-${section.name}-count'),
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    ),
  );
}

class _InboxRow extends ConsumerWidget {
  const _InboxRow({
    required this.item,
    required this.onOpen,
    required this.isPostponed,
    required this.actionInProgress,
  });

  final InboxItem item;
  final VoidCallback onOpen;
  final bool isPostponed;
  final bool actionInProgress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final _Preview preview = _preview(item);
    final bool isUnavailable = item is UnavailablePostponedInboxItem;
    final bool canOpen = !isUnavailable;
    return Semantics(
      key: ValueKey<String>('unavailable-postponed-${item.key}'),
      container: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Semantics(
                    button: canOpen,
                    enabled: canOpen,
                    label: isUnavailable
                        ? InboxStrings.unavailablePostponedSemantics
                        : InboxStrings.itemSemantics(
                            preview.title,
                            preview.body,
                          ),
                    hint: canOpen ? InboxStrings.openItemHint : null,
                    onTap: canOpen ? onOpen : null,
                    child: ExcludeSemantics(
                      child: Focus(
                        key: ValueKey<String>('inbox-focus-${item.key}'),
                        debugLabel: 'inbox-row-${item.key}',
                        canRequestFocus: canOpen,
                        onFocusChange: (bool hasFocus) {
                          if (hasFocus) {
                            ref
                                .read(inboxPageProvider.notifier)
                                .focusItem(item.key);
                          }
                        },
                        onKeyEvent: (FocusNode node, KeyEvent event) {
                          if (canOpen &&
                              event is KeyDownEvent &&
                              (event.logicalKey == LogicalKeyboardKey.enter ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.space)) {
                            onOpen();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: InkWell(
                          key: ValueKey<String>('inbox-item-${item.key}'),
                          canRequestFocus: false,
                          onTap: canOpen ? onOpen : null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                preview.title,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                preview.body,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!isPostponed) ...<Widget>[
                  _InboxIconAction(
                    key: ValueKey<String>('read-${item.key}'),
                    label: InboxStrings.read,
                    onPressed: actionInProgress
                        ? null
                        : () => unawaited(_markRead(context, ref)),
                    icon: Icons.done,
                  ),
                  _InboxIconAction(
                    key: ValueKey<String>('postpone-${item.key}'),
                    label: InboxStrings.postpone,
                    onPressed: actionInProgress
                        ? null
                        : () => unawaited(_postpone(context, ref)),
                    icon: Icons.schedule,
                  ),
                ] else
                  _InboxIconAction(
                    key: ValueKey<String>('remove-${item.key}'),
                    label: InboxStrings.remove,
                    onPressed: actionInProgress
                        ? null
                        : () => unawaited(_remove(context, ref)),
                    icon: Icons.delete_outline,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _markRead(BuildContext context, WidgetRef ref) async {
    if (!await ref.read(inboxPageProvider.notifier).markRead(item) &&
        context.mounted) {
      _showFailure(context, InboxStrings.markReadFailed);
    }
  }

  Future<void> _postpone(BuildContext context, WidgetRef ref) async {
    if (!await ref.read(inboxPageProvider.notifier).postpone(item) &&
        context.mounted) {
      _showFailure(context, InboxStrings.postponeFailed);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    if (!await ref.read(inboxPageProvider.notifier).remove(item) &&
        context.mounted) {
      _showFailure(context, InboxStrings.removeFailed);
    }
  }

  void _showFailure(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  _Preview _preview(InboxItem item) => switch (item) {
    ThreadInboxItem(thread: final thread) => _Preview(
      thread.root.author.displayName,
      thread.root.message.isEmpty ? InboxStrings.thread : thread.root.message,
    ),
    ChannelPostInboxItem(post: final post) => _Preview(
      post.author.displayName,
      post.message,
    ),
    DirectMessageBundleInboxItem(messages: final messages) => _Preview(
      messages.first.post.author.displayName,
      messages.length == 1
          ? messages.first.post.message
          : InboxStrings.messages(messages.length),
    ),
    UnavailablePostponedInboxItem() => const _Preview(
      InboxStrings.unavailablePostponedTitle,
      InboxStrings.unavailablePostponedBody,
    ),
  };
}

class _InboxIconAction extends StatelessWidget {
  const _InboxIconAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: label,
    onTap: onPressed,
    child: ExcludeSemantics(
      child: IconButton(
        tooltip: label,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        icon: Icon(icon),
      ),
    ),
  );
}

class _InboxTextAction extends StatelessWidget {
  const _InboxTextAction({
    required this.label,
    required this.semanticsLabel,
    required this.onPressed,
    this.outlined = false,
  });

  final String label;
  final String semanticsLabel;
  final VoidCallback? onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final ButtonStyle style = TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      tapTargetSize: MaterialTapTargetSize.padded,
    );
    final Widget button = outlined
        ? OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text(label),
          )
        : TextButton(onPressed: onPressed, style: style, child: Text(label));
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticsLabel,
      onTap: onPressed,
      child: ExcludeSemantics(child: button),
    );
  }
}

final class _Preview {
  const _Preview(this.title, this.body);

  final String title;
  final String body;
}
