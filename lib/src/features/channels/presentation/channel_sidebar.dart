import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/auth_controller.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';
import 'package:mattermost_flutter/src/features/channels/presentation/channel_sidebar_controller.dart';
import 'package:mattermost_flutter/src/features/channels/presentation/channel_sidebar_strings.dart';

class ChannelSidebar extends ConsumerWidget {
  const ChannelSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AuthState auth = ref.watch(authControllerProvider);
    if (auth.phase != AuthPhase.signedIn) {
      return const SafeArea(
        child: Center(child: Text(ChannelSidebarStrings.title)),
      );
    }

    final AsyncValue<ChannelSidebarSnapshot> sidebar = ref.watch(
      channelSidebarProvider,
    );
    return SafeArea(
      child: sidebar.when(
        loading: () => Center(
          child: Semantics(
            label: ChannelSidebarStrings.loading,
            child: const CircularProgressIndicator(),
          ),
        ),
        error: (Object error, StackTrace stackTrace) =>
            _InitialError(onRetry: () => unawaited(refreshChannelSidebar(ref))),
        data: (ChannelSidebarSnapshot snapshot) => _SidebarContent(
          snapshot: snapshot,
          onRefresh: () => refreshChannelSidebar(ref),
        ),
      ),
    );
  }
}

class _InitialError extends StatelessWidget {
  const _InitialError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            ChannelSidebarStrings.loadFailed,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text(ChannelSidebarStrings.retry),
          ),
        ],
      ),
    ),
  );
}

class _SidebarContent extends StatelessWidget {
  const _SidebarContent({required this.snapshot, required this.onRefresh});

  final ChannelSidebarSnapshot snapshot;
  final RefreshCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TeamHeader(team: snapshot.team, onRefresh: onRefresh),
        if (snapshot.isRefreshing) const LinearProgressIndicator(minHeight: 2),
        if (snapshot.refreshFailed)
          const MaterialBanner(
            content: Text(ChannelSidebarStrings.refreshFailed),
            actions: <Widget>[SizedBox.shrink()],
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
        Expanded(
          child: snapshot.sections.isEmpty
              ? const Center(child: Text(ChannelSidebarStrings.empty))
              : RefreshIndicator(
                  onRefresh: onRefresh,
                  child: _LazyChannelList(sections: snapshot.sections),
                ),
        ),
      ],
    );
  }
}

class _TeamHeader extends StatelessWidget {
  const _TeamHeader({required this.team, required this.onRefresh});

  final SidebarTeam? team;
  final RefreshCallback onRefresh;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(
      team?.displayName ?? ChannelSidebarStrings.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleMedium,
    ),
    trailing: IconButton(
      tooltip: ChannelSidebarStrings.refresh,
      onPressed: () => unawaited(onRefresh()),
      icon: const Icon(Icons.refresh),
    ),
  );
}

class _LazyChannelList extends StatefulWidget {
  const _LazyChannelList({required this.sections});

  final List<SidebarSection> sections;

  @override
  State<_LazyChannelList> createState() => _LazyChannelListState();
}

class _LazyChannelListState extends State<_LazyChannelList> {
  static const String _pageStorageIdentifier = 'collapsed-channel-sections';

  final Set<String> _collapsedSectionIds = <String>{};
  bool _restoredFromPageStorage = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoredFromPageStorage) return;

    _restoredFromPageStorage = true;
    final Object? storedIds = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: _pageStorageIdentifier);
    if (storedIds case final List<Object?> ids) {
      _collapsedSectionIds.addAll(ids.whereType<String>());
    }
  }


  @override
  Widget build(BuildContext context) {
    final _ChannelListIndex index = _ChannelListIndex(
      sections: widget.sections,
      collapsedSectionIds: _collapsedSectionIds,
    );
    return ListView.builder(
      key: const PageStorageKey<String>('channel-sidebar'),
      itemCount: index.rowCount,
      itemBuilder: (BuildContext context, int rowIndex) {
        final _ChannelListRow row = index.rowAt(rowIndex);
        final SidebarSection section = widget.sections[row.sectionIndex];
        if (row.channelIndex == null) {
          final bool isExpanded = !_collapsedSectionIds.contains(section.id);
          return _ChannelSectionHeader(
            key: ValueKey<String>('channel-section-${section.id}'),
            section: section,
            isExpanded: isExpanded,
            onTap: () => _toggleSection(section.id),
          );
        }
        final SidebarChannel channel = section.channels[row.channelIndex!];
        return _ChannelTile(
          key: ValueKey<String>('channel-${channel.id}'),
          channel: channel,
        );
      },
    );
  }

  void _toggleSection(String sectionId) {
    setState(() {
      if (!_collapsedSectionIds.add(sectionId)) {
        _collapsedSectionIds.remove(sectionId);
      }
    });
    PageStorage.maybeOf(context)?.writeState(
      context,
      _collapsedSectionIds.toList(growable: false),
      identifier: _pageStorageIdentifier,
    );
  }
}

/// Maps a flat, lazily built list index to a section or channel without
/// allocating a row descriptor for every channel whenever a section toggles.
final class _ChannelListIndex {
  _ChannelListIndex({
    required this.sections,
    required Set<String> collapsedSectionIds,
  }) {
    var nextStart = 0;
    for (final SidebarSection section in sections) {
      _sectionStarts.add(nextStart);
      nextStart += 1;
      if (!collapsedSectionIds.contains(section.id)) {
        nextStart += section.channels.length;
      }
    }
    rowCount = nextStart;
  }

  final List<SidebarSection> sections;
  final List<int> _sectionStarts = <int>[];
  late final int rowCount;

  _ChannelListRow rowAt(int rowIndex) {
    var low = 0;
    var high = _sectionStarts.length - 1;
    while (low < high) {
      final int middle = (low + high + 1) >> 1;
      if (_sectionStarts[middle] <= rowIndex) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    final int offset = rowIndex - _sectionStarts[low];
    return _ChannelListRow(
      sectionIndex: low,
      channelIndex: offset == 0 ? null : offset - 1,
    );
  }
}

final class _ChannelListRow {
  const _ChannelListRow({required this.sectionIndex, this.channelIndex});

  final int sectionIndex;
  final int? channelIndex;
}

class _ChannelSectionHeader extends StatelessWidget {
  const _ChannelSectionHeader({
    required super.key,
    required this.section,
    required this.isExpanded,
    required this.onTap,
  });

  final SidebarSection section;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    expanded: isExpanded,
    child: ListTile(
      title: Text(
        section.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelLarge,
      ),
      trailing: AnimatedRotation(
        turns: isExpanded ? 0.5 : 0,
        duration: const Duration(milliseconds: 150),
        child: const Icon(Icons.expand_more),
      ),
      onTap: onTap,
    ),
  );
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required super.key, required this.channel});

  final SidebarChannel channel;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: Icon(_iconFor(channel.kind), size: 18),
    title: Text(
      channel.displayName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: () {
      final ScaffoldState? scaffold = Scaffold.maybeOf(context);
      if (scaffold?.isDrawerOpen ?? false) Navigator.of(context).pop();
    },
  );

  IconData _iconFor(ChannelKind kind) => switch (kind) {
    ChannelKind.publicChannel => Icons.tag,
    ChannelKind.privateChannel => Icons.lock_outline,
    ChannelKind.directMessage => Icons.person_outline,
    ChannelKind.groupMessage => Icons.group_outlined,
  };
}
