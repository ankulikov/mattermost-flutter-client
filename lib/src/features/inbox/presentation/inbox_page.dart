import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_controller.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_content.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';
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
    final Iterable<InboxItem> expandedItems = isPostponed
        ? items.expand(_postponedPresentationItems)
        : items;
    final List<InboxItem> presentationItems = expandedItems.toList()
      ..sort((InboxItem first, InboxItem second) {
        final int byActivity = second.lastActivityAt.compareTo(
          first.lastActivityAt,
        );
        return byActivity != 0 ? byActivity : first.key.compareTo(second.key);
      });
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool expanded = constraints.maxWidth >= 700;
        return ListView.builder(
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 24 : 8,
            vertical: 12,
          ),
          itemCount: presentationItems.length,
          itemBuilder: (BuildContext context, int index) {
            final InboxItem item = presentationItems[index];
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _InboxRow(
                    item: item,
                    onOpen: () => onOpenItem(item),
                    isPostponed: isPostponed,
                  ),
                ),
              ),
            );
          },
        );
      },
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
    final AuthSession? session = ref.watch(authSessionProvider);
    final ThemeData theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            InkWell(
              key: ValueKey<String>('inbox-item-${item.key}'),
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    MessageAvatar(author: preview.post.author),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            preview.source,
                            key: ValueKey<String>('inbox-source-${item.key}'),
                            style: theme.textTheme.labelLarge,
                          ),
                          _InboxAuthorLine(
                            author: preview.post.author,
                            sentAt: preview.post.sentAt,
                          ),
                          const SizedBox(height: 6),
                          MessageContent(
                            post: preview.post,
                            serverUrl: session?.serverUrl,
                          ),
                        ],
                      ),
                    ),
                    if (preview.unreadCount case final int count) ...<Widget>[
                      const SizedBox(width: 8),
                      Semantics(
                        label: InboxStrings.unreadMessages(count),
                        child: Badge(
                          key: ValueKey<String>('unread-${item.key}'),
                          label: Text('$count'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: isPostponed
                  ? TextButton.icon(
                      key: ValueKey<String>('remove-${item.key}'),
                      onPressed: () => unawaited(_remove(context, ref)),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text(InboxStrings.remove),
                    )
                  : _NewItemActions(
                      itemKey: item.key,
                      onRead: () => unawaited(_markRead(context, ref)),
                      onPostpone: () => unawaited(_postpone(context, ref)),
                    ),
            ),
          ],
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
    ThreadInboxItem(thread: final thread, channel: final channel) => _Preview(
      source: InboxStrings.threadInChannel(_channelName(channel)),
      post: thread.root,
      unreadCount: thread.unreadReplies,
    ),
    ChannelPostInboxItem(candidate: final candidate) => _Preview(
      source: _channelPostSource(candidate),
      post: candidate.post,
    ),
    DirectMessageBundleInboxItem(messages: final messages) => _Preview(
      source: InboxStrings.directMessage,
      post: messages.last.post,
      unreadCount: messages.length,
    ),
  };

  String _channelPostSource(InboxPostCandidate candidate) =>
      switch (candidate.reason) {
        InboxAttentionReason.groupMention => InboxStrings.groupMentionInChannel(
          _groupTag(candidate),
          _channelName(candidate.channel),
        ),
        InboxAttentionReason.directMention =>
          InboxStrings.youMentionedInChannel(_channelName(candidate.channel)),
        InboxAttentionReason.keywordMention ||
        InboxAttentionReason.channelMention ||
        InboxAttentionReason.allMessagesSubscription => _channelName(
          candidate.channel,
        ),
      };

  String _channelName(SidebarChannel channel) =>
      channel.displayName.trim().isEmpty ? channel.name : channel.displayName;

  String _groupTag(InboxPostCandidate candidate) {
    final String? handle = candidate.groupMentionHandle;
    if (handle != null && handle.trim().isNotEmpty) return handle;
    return InboxStrings.groupMentionFallback;
  }
}

class _NewItemActions extends StatelessWidget {
  const _NewItemActions({
    required this.itemKey,
    required this.onRead,
    required this.onPostpone,
  });

  final String itemKey;
  final VoidCallback onRead;
  final VoidCallback onPostpone;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final bool stack =
          constraints.maxWidth < 320 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.3;
      final Widget read = TextButton.icon(
        key: ValueKey<String>('read-$itemKey'),
        onPressed: onRead,
        icon: const Icon(Icons.done),
        label: const Text(InboxStrings.read),
      );
      final Widget postpone = TextButton.icon(
        key: ValueKey<String>('postpone-$itemKey'),
        onPressed: onPostpone,
        icon: const Icon(Icons.schedule),
        label: const Text(InboxStrings.postpone),
      );
      if (stack) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[read, const Divider(height: 1), postpone],
        );
      }
      return Row(
        children: <Widget>[
          Expanded(child: read),
          const SizedBox(height: 36, child: VerticalDivider(width: 1)),
          Expanded(child: postpone),
        ],
      );
    },
  );
}

class _InboxAuthorLine extends StatelessWidget {
  const _InboxAuthorLine({required this.author, required this.sentAt});

  final PostAuthor author;
  final DateTime sentAt;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          author.displayName,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          formatMessageTimestamp(
            sentAt: sentAt,
            locale: Localizations.localeOf(context).toLanguageTag(),
          ),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

final class _Preview {
  const _Preview({required this.source, required this.post, this.unreadCount});

  final String source;
  final Post post;
  final int? unreadCount;
}
