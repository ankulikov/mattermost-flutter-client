import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_controller.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_strings.dart';
import 'package:mattermost_flutter/src/ui/threads/thread_route.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

class InboxPage extends ConsumerStatefulWidget {
  const InboxPage({
    required this.channelsById,
    required this.onSelectChannel,
    super.key,
  });

  final Map<String, SidebarChannel> channelsById;
  final ValueChanged<String> onSelectChannel;

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
        title: const Text(InboxStrings.title),
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
          tabs: const <Tab>[
            Tab(text: InboxStrings.newItems),
            Tab(text: InboxStrings.postponed),
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
            if (state.isRefreshing) const LinearProgressIndicator(minHeight: 2),
            if (state.refreshFailed)
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
                    channelsById: widget.channelsById,
                    onSelectChannel: widget.onSelectChannel,
                    isPostponed: false,
                  ),
                  _InboxList(
                    items: state.snapshot.postponedItems,
                    empty: InboxStrings.emptyPostponed,
                    channelsById: widget.channelsById,
                    onSelectChannel: widget.onSelectChannel,
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

class _InboxList extends StatelessWidget {
  const _InboxList({
    required this.items,
    required this.empty,
    required this.channelsById,
    required this.onSelectChannel,
    required this.isPostponed,
  });
  final List<InboxItem> items;
  final String empty;
  final Map<String, SidebarChannel> channelsById;
  final ValueChanged<String> onSelectChannel;
  final bool isPostponed;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return Center(child: Text(empty));
    final List<InboxItem> people = items
        .where(
          (InboxItem item) =>
              item is! DirectMessageBundleInboxItem ||
              item.automationClass.name == 'person',
        )
        .toList();
    final List<InboxItem> bots = items
        .whereType<DirectMessageBundleInboxItem>()
        .where(
          (DirectMessageBundleInboxItem item) =>
              item.automationClass.name != 'person',
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        if (people.isNotEmpty) ..._section(context, people, null),
        if (bots.isNotEmpty) ..._section(context, bots, InboxStrings.bots),
      ],
    );
  }

  List<Widget> _section(
    BuildContext context,
    List<InboxItem> items,
    String? label,
  ) => <Widget>[
    if (label != null)
      Padding(
        padding: const EdgeInsets.only(left: 4, top: 8, bottom: 4),
        child: Text(label, style: Theme.of(context).textTheme.titleSmall),
      ),
    for (final InboxItem item in items)
      _InboxCard(
        item: item,
        channelsById: channelsById,
        onSelectChannel: onSelectChannel,
        isPostponed: isPostponed,
      ),
  ];
}

class _InboxCard extends ConsumerWidget {
  const _InboxCard({
    required this.item,
    required this.channelsById,
    required this.onSelectChannel,
    required this.isPostponed,
  });
  final InboxItem item;
  final Map<String, SidebarChannel> channelsById;
  final ValueChanged<String> onSelectChannel;
  final bool isPostponed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final _Preview preview = _preview(item);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(preview.title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(preview.body, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: () => _open(context),
                  child: const Text(InboxStrings.open),
                ),
                if (!isPostponed)
                  OutlinedButton(
                    onPressed: () => unawaited(_postpone(context, ref)),
                    child: const Text(InboxStrings.postpone),
                  ),
                if (isPostponed)
                  OutlinedButton(
                    onPressed: () => unawaited(_remove(context, ref)),
                    child: const Text(InboxStrings.remove),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _postpone(BuildContext context, WidgetRef ref) async {
    if (!await ref.read(inboxProvider.notifier).postpone(item) &&
        context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(InboxStrings.refreshFailed)));
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    if (!await ref.read(inboxProvider.notifier).remove(item) &&
        context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(InboxStrings.refreshFailed)));
    }
  }

  void _open(BuildContext context) {
    if (item case ThreadInboxItem(thread: final thread)) {
      final SidebarChannel? channel = channelsById[thread.root.channelId];
      if (channel == null) return;
      unawaited(
        ThreadRoute.open(
          context,
          ThreadRouteArguments(
            rootPostId: thread.id,
            channel: channel,
            unreadReplies: thread.unreadReplies,
            positionAtEndWhenRead: thread.unreadReplies == 0,
            onSelectChannel: onSelectChannel,
          ),
        ),
      );
      return;
    }
    final String channelId = switch (item) {
      ChannelPostInboxItem(post: final post) => post.channelId,
      DirectMessageBundleInboxItem(channelId: final channelId) => channelId,
      ThreadInboxItem() => '',
    };
    final SidebarChannel? channel = channelsById[channelId];
    if (channel != null) {
      // TODO(inbox): pass the Inbox post id into ChannelPostsPane and mark the
      // viewed channel/thread read. MVP opens the selected channel only.
      onSelectChannel(channel.name);
    }
  }

  _Preview _preview(InboxItem item) => switch (item) {
    ThreadInboxItem(thread: final thread) => _Preview(
      InboxStrings.thread,
      thread.root.message.isEmpty
          ? thread.root.author.displayName
          : thread.root.message,
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
