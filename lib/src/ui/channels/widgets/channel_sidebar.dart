import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/ui/auth/auth_controller.dart';
import 'package:mattermost_flutter/src/ui/channels/channel_sidebar_controller.dart';
import 'package:mattermost_flutter/src/ui/channels/channel_sidebar_strings.dart';
import 'package:mattermost_flutter/src/ui/channels/selected_channel_controller.dart';
import 'package:mattermost_flutter/src/ui/channels/widgets/channel_avatar.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

class ChannelSidebar extends ConsumerWidget {
  const ChannelSidebar({this.onChannelSelected, super.key});

  final VoidCallback? onChannelSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AuthState auth = ref.watch(authControllerProvider);
    if (auth.phase != AuthPhase.signedIn) {
      return const SafeArea(
        child: Center(child: Text(ChannelSidebarStrings.title)),
      );
    }

    final AsyncValue<ChannelSidebarViewState> sidebar = ref.watch(
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
        data: (ChannelSidebarViewState viewState) => _SidebarContent(
          snapshot: viewState.snapshot,
          refreshStatus: viewState.refreshStatus,
          onRefresh: () => refreshChannelSidebar(ref),
          onChannelSelected: onChannelSelected,
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

class _SidebarContent extends StatefulWidget {
  const _SidebarContent({
    required this.snapshot,
    required this.refreshStatus,
    required this.onRefresh,
    required this.onChannelSelected,
  });

  final ChannelSidebarSnapshot snapshot;
  final OperationStatus refreshStatus;
  final RefreshCallback onRefresh;
  final VoidCallback? onChannelSelected;

  @override
  State<_SidebarContent> createState() => _SidebarContentState();
}

class _SidebarContentState extends State<_SidebarContent> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<SidebarSection> get _filteredSections {
    final String normalizedQuery = _query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return widget.snapshot.sections;

    return widget.snapshot.sections
        .map((SidebarSection section) {
          final List<SidebarChannel> channels = section.channels
              .where(
                (SidebarChannel channel) =>
                    channel.displayName.toLowerCase().contains(normalizedQuery),
              )
              .toList(growable: false);
          return SidebarSection(
            id: section.id,
            displayName: section.displayName,
            channels: channels,
            collapsed: section.collapsed,
            muted: section.muted,
            sorting: section.sorting,
          );
        })
        .where((SidebarSection section) => section.channels.isNotEmpty)
        .toList(growable: false);
  }

  bool get _hasSearchQuery => _query.trim().isNotEmpty;
  bool get _hasSearchText => _query.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final List<SidebarSection> filteredSections = _filteredSections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TeamHeader(team: widget.snapshot.team, onRefresh: widget.onRefresh),
        if (widget.refreshStatus is OperationInProgress)
          const LinearProgressIndicator(minHeight: 2),
        if (widget.refreshStatus is OperationFailed)
          const MaterialBanner(
            content: Text(ChannelSidebarStrings.refreshFailed),
            actions: <Widget>[SizedBox.shrink()],
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            key: const ValueKey<String>('channel-search-field'),
            controller: _searchController,
            focusNode: _searchFocusNode,
            autocorrect: false,
            textInputAction: TextInputAction.search,
            onChanged: _updateQuery,
            onSubmitted: (_) => _searchFocusNode.unfocus(),
            onTapOutside: (_) => _searchFocusNode.unfocus(),
            decoration: InputDecoration(
              hintText: ChannelSidebarStrings.searchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _hasSearchText
                  ? IconButton(
                      tooltip: ChannelSidebarStrings.clearSearch,
                      onPressed: _clearSearch,
                      icon: const Icon(Icons.close),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(width: 1),
              ),
            ),
          ),
        ),
        Expanded(
          child: filteredSections.isEmpty
              ? Center(
                  child: Text(
                    _hasSearchQuery
                        ? ChannelSidebarStrings.noSearchResults
                        : ChannelSidebarStrings.empty,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  child: _LazyChannelList(
                    sections: filteredSections,
                    expandSections: _hasSearchQuery,
                    onChannelSelected: widget.onChannelSelected,
                  ),
                ),
        ),
      ],
    );
  }

  void _updateQuery(String value) {
    if (value == _query) return;
    setState(() => _query = value);
  }

  void _clearSearch() {
    _searchController.clear();
    _updateQuery('');
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

class _LazyChannelList extends ConsumerStatefulWidget {
  const _LazyChannelList({
    required this.sections,
    required this.expandSections,
    required this.onChannelSelected,
  });

  final List<SidebarSection> sections;
  final bool expandSections;
  final VoidCallback? onChannelSelected;

  @override
  ConsumerState<_LazyChannelList> createState() => _LazyChannelListState();
}

class _LazyChannelListState extends ConsumerState<_LazyChannelList> {
  static const String _pageStorageIdentifier = 'collapsed-channel-sections';

  final Set<String> _collapsedSectionIds = <String>{};
  final Set<String> _initializedSectionIds = <String>{};
  bool _restoredFromPageStorage = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoredFromPageStorage) return;

    _restoredFromPageStorage = true;
    final Object? storedIds = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: _pageStorageIdentifier);
    if (storedIds case <String, Object?>{
      'collapsed': final List<Object?> collapsed,
      'initialized': final List<Object?> initialized,
    }) {
      _collapsedSectionIds.addAll(collapsed.whereType<String>());
      _initializedSectionIds.addAll(initialized.whereType<String>());
    } else if (storedIds case final List<Object?> ids) {
      _collapsedSectionIds.addAll(ids.whereType<String>());
      _initializedSectionIds.addAll(
        widget.sections.map((SidebarSection section) => section.id),
      );
    }
    _applyServerDefaults();
  }

  @override
  void didUpdateWidget(_LazyChannelList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyServerDefaults();
  }

  void _applyServerDefaults() {
    for (final SidebarSection section in widget.sections) {
      if (_initializedSectionIds.add(section.id) && section.collapsed) {
        _collapsedSectionIds.add(section.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Set<String> collapsedSectionIds = widget.expandSections
        ? const <String>{}
        : _collapsedSectionIds;
    final _ChannelListIndex index = _ChannelListIndex(
      sections: widget.sections,
      collapsedSectionIds: collapsedSectionIds,
    );
    return ListView.builder(
      key: const PageStorageKey<String>('channel-sidebar'),
      itemCount: index.rowCount,
      itemBuilder: (BuildContext context, int rowIndex) {
        final _ChannelListRow row = index.rowAt(rowIndex);
        final SidebarSection section = widget.sections[row.sectionIndex];
        if (row.channelIndex == null) {
          final bool isExpanded = !collapsedSectionIds.contains(section.id);
          return _ChannelSectionHeader(
            key: ValueKey<String>('channel-section-${section.id}'),
            section: section,
            isExpanded: isExpanded,
            onTap: widget.expandSections
                ? null
                : () => _toggleSection(section.id),
          );
        }
        final SidebarChannel channel = section.channels[row.channelIndex!];
        return _ChannelTile(
          key: ValueKey<String>('channel-${channel.id}'),
          channel: channel,
          muted: section.muted || channel.muted,
          selected: ref.watch(
            selectedChannelProvider.select(
              (SidebarChannel? selected) => selected?.id == channel.id,
            ),
          ),
          onTap: () => _selectChannel(channel),
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
    PageStorage.maybeOf(context)?.writeState(context, <String, Object?>{
      'collapsed': _collapsedSectionIds.toList(growable: false),
      'initialized': _initializedSectionIds.toList(growable: false),
    }, identifier: _pageStorageIdentifier);
  }

  void _selectChannel(SidebarChannel channel) {
    ref
        .read(shellDestinationProvider.notifier)
        .select(ShellDestination.channels);
    ref.read(selectedChannelProvider.notifier).select(channel);
    final ScaffoldState? scaffold = Scaffold.maybeOf(context);
    if (scaffold?.isDrawerOpen ?? false) Navigator.of(context).pop();
    widget.onChannelSelected?.call();
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    expanded: isExpanded,
    child: Opacity(
      opacity: section.muted ? 0.55 : 1,
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
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
      ),
    ),
  );
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required super.key,
    required this.channel,
    required this.muted,
    required this.selected,
    required this.onTap,
  });

  final SidebarChannel channel;
  final bool muted;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool highlightUnread = channel.isUnread && !muted;
    final RoundedRectangleBorder shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    return Opacity(
      opacity: muted ? 0.55 : 1,
      child: Material(
        key: ValueKey<String>('channel-selection-surface-${channel.id}'),
        color: selected ? colors.secondaryContainer : Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -2),
          selected: selected,
          shape: shape,
          leading: IconTheme(
            data: theme.iconTheme.copyWith(
              color: selected
                  ? colors.onSecondaryContainer
                  : highlightUnread
                  ? colors.onSurface
                  : colors.onSurfaceVariant,
            ),
            child: ChannelAvatar(channel: channel),
          ),
          title: Text(
            channel.displayName,
            semanticsLabel: highlightUnread
                ? ChannelSidebarStrings.unreadChannel(channel.displayName)
                : channel.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // Let ListTile provide its established typography and colors.
            // Unread rows only add their emphasis, keeping all other channel
            // rows visually identical to the pre-unread-highlight sidebar.
            style: highlightUnread
                ? const TextStyle(fontWeight: FontWeight.w600)
                : const TextStyle(fontWeight: FontWeight.w300),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
