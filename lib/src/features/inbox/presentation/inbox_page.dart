import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/classify_inbox_section.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_controller.dart';
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
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<InboxViewState> value = ref.watch(inboxProvider);
    return Scaffold(
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
          IconButton(
            tooltip: InboxStrings.refresh,
            onPressed: () =>
                unawaited(ref.read(inboxProvider.notifier).refresh()),
            icon: const Icon(Icons.refresh),
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
              OutlinedButton(
                onPressed: () => ref.invalidate(inboxProvider),
                child: const Text(InboxStrings.retry),
              ),
            ],
          ),
        ),
        data: (InboxViewState state) => Column(
          children: <Widget>[
            if (state.refreshStatus is OperationInProgress)
              const LinearProgressIndicator(minHeight: 2),
            if (state.refreshStatus is OperationFailed)
              const MaterialBanner(
                content: Text(InboxStrings.refreshFailed),
                actions: <Widget>[SizedBox.shrink()],
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
                  ),
                  _InboxList(
                    items: state.snapshot.postponedItems,
                    empty: InboxStrings.emptyPostponed,
                    onOpenItem: widget.onOpenItem,
                    isPostponed: true,
                  ),
                ],
              ),
            ),
          ],
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
    final String label = switch (status) {
      InboxConnectionStatus.connecting => InboxStrings.connecting,
      InboxConnectionStatus.connected => InboxStrings.connected,
      InboxConnectionStatus.disconnected => InboxStrings.disconnected,
    };
    return Tooltip(
      message: label,
      child: Semantics(
        key: const ValueKey<String>('inbox-connection-indicator'),
        label: label,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: switch (status) {
              InboxConnectionStatus.connecting => Colors.amber,
              InboxConnectionStatus.connected => Colors.green,
              InboxConnectionStatus.disconnected => Colors.red,
            },
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
  });

  final List<InboxItem> items;
  final String empty;
  final ValueChanged<InboxItem> onOpenItem;
  final bool isPostponed;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return Center(child: Text(empty));
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: <Widget>[
        for (final InboxSection section in InboxSection.values)
          if (sections[section]!.isNotEmpty) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Text(
                _sectionLabel(section),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final InboxItem item in sections[section]!)
              _InboxRow(
                item: item,
                onOpen: () => onOpenItem(item),
                isPostponed: isPostponed,
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
    InboxSection.groupMentions => InboxStrings.groupMention,
    InboxSection.botsAndIntegrations => InboxStrings.bots,
    InboxSection.directMessages => InboxStrings.directMessages,
    InboxSection.threads => InboxStrings.threads,
  };
}

class _InboxRow extends ConsumerWidget {
  const _InboxRow({
    required this.item,
    required this.onOpen,
    required this.isPostponed,
  });

  final InboxItem item;
  final VoidCallback onOpen;
  final bool isPostponed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final _Preview preview = _preview(item);
    return InkWell(
      key: ValueKey<String>('inbox-item-${item.key}'),
      onTap: onOpen,
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
              const SizedBox(width: 8),
              if (!isPostponed) ...<Widget>[
                IconButton(
                  key: ValueKey<String>('read-${item.key}'),
                  tooltip: InboxStrings.read,
                  onPressed: () => unawaited(_markRead(context, ref)),
                  icon: const Icon(Icons.done),
                ),
                IconButton(
                  key: ValueKey<String>('postpone-${item.key}'),
                  tooltip: InboxStrings.postpone,
                  onPressed: () => unawaited(_postpone(context, ref)),
                  icon: const Icon(Icons.schedule),
                ),
              ] else
                IconButton(
                  key: ValueKey<String>('remove-${item.key}'),
                  tooltip: InboxStrings.remove,
                  onPressed: () => unawaited(_remove(context, ref)),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _markRead(BuildContext context, WidgetRef ref) async {
    if (!await ref.read(inboxProvider.notifier).markRead(item) &&
        context.mounted) {
      _showFailure(context, InboxStrings.markReadFailed);
    }
  }

  Future<void> _postpone(BuildContext context, WidgetRef ref) async {
    if (!await ref.read(inboxProvider.notifier).postpone(item) &&
        context.mounted) {
      _showFailure(context, InboxStrings.postponeFailed);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    if (!await ref.read(inboxProvider.notifier).remove(item) &&
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
  };
}

final class _Preview {
  const _Preview(this.title, this.body);

  final String title;
  final String body;
}
