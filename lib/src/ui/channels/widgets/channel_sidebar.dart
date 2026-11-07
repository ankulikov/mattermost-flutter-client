import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/repositories/sidebar_view_preferences_repository.dart';
import 'package:mattermost_flutter/src/ui/auth/auth_controller.dart';
import 'package:mattermost_flutter/src/ui/channels/channel_sidebar_controller.dart';
import 'package:mattermost_flutter/src/ui/channels/channel_sidebar_strings.dart';
import 'package:mattermost_flutter/src/ui/channels/selected_channel_controller.dart';
import 'package:mattermost_flutter/src/ui/channels/widgets/channel_avatar.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_spacing.dart';
import 'package:mattermost_flutter/src/ui/threads/followed_threads_controller.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

const RoundedRectangleBorder _sidebarTileShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(AppSpacing.sm)),
);

enum _ChannelMenuAction { unread, favorite, mute, move, close, leave }

class ChannelSidebar extends ConsumerWidget {
  const ChannelSidebar({
    this.onChannelSelected,
    this.onThreadsSelected,
    this.showTeamHeader = true,
    super.key,
  });

  final VoidCallback? onChannelSelected;
  final VoidCallback? onThreadsSelected;
  final bool showTeamHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AuthState auth = ref.watch(authControllerProvider);
    if (auth.phase != AuthPhase.signedIn || auth.session == null) {
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
        data: (ChannelSidebarViewState viewState) {
          final SidebarTeam? team = viewState.snapshot.team;
          final bool threadsUnread =
              team != null &&
              ref.watch(
                followedThreadsProvider(team.id).select(
                  (AsyncValue<FollowedThreadsViewState> value) =>
                      (value.asData?.value.totalUnreadThreads ?? 0) > 0,
                ),
              );
          return _SidebarContent(
            key: ValueKey<String>(auth.session!.durableDataScopeId),
            accountScopeId: auth.session!.durableDataScopeId,
            preferencesRepository: ref.read(
              sidebarViewPreferencesRepositoryProvider,
            ),
            snapshot: viewState.snapshot,
            refreshStatus: viewState.refreshStatus,
            onRefresh: () => refreshChannelSidebar(ref),
            showTeamHeader: showTeamHeader,
            onChannelSelected: onChannelSelected,
            threadsSelected:
                ref.watch(shellDestinationProvider) == ShellDestination.threads,
            threadsUnread: threadsUnread,
            onThreadsSelected: () {
              ref
                  .read(shellDestinationProvider.notifier)
                  .select(ShellDestination.threads);
              onThreadsSelected?.call();
            },
          );
        },
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
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            ChannelSidebarStrings.loadFailed,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
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
    required this.accountScopeId,
    required this.preferencesRepository,
    required this.snapshot,
    required this.refreshStatus,
    required this.onRefresh,
    required this.showTeamHeader,
    required this.onChannelSelected,
    required this.threadsSelected,
    required this.threadsUnread,
    required this.onThreadsSelected,
    super.key,
  });

  final String accountScopeId;
  final SidebarViewPreferencesRepository preferencesRepository;
  final ChannelSidebarSnapshot snapshot;
  final OperationStatus refreshStatus;
  final RefreshCallback onRefresh;
  final bool showTeamHeader;
  final VoidCallback? onChannelSelected;
  final bool threadsSelected;
  final bool threadsUnread;
  final VoidCallback onThreadsSelected;

  @override
  State<_SidebarContent> createState() => _SidebarContentState();
}

class _SidebarContentState extends State<_SidebarContent> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _query = '';
  bool _hideReadChannels = false;
  bool _hideFolderHeadings = false;
  bool _preferencesLoaded = false;
  bool _savingPreferences = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
    unawaited(_loadPreferences());
  }

  Future<void> _loadPreferences() async {
    SidebarViewPreferences preferences;
    try {
      preferences = await widget.preferencesRepository.read(
        widget.accountScopeId,
      );
    } on Object {
      preferences = const SidebarViewPreferences();
    }
    if (!mounted) return;
    setState(() {
      _hideReadChannels = preferences.hideReadChannels;
      _hideFolderHeadings = preferences.hideFolderHeadings;
      _preferencesLoaded = true;
    });
  }

  void _savePreferences({bool? hideReadChannels, bool? hideFolderHeadings}) {
    if (_savingPreferences) return;
    final SidebarViewPreferences previous = SidebarViewPreferences(
      hideReadChannels: _hideReadChannels,
      hideFolderHeadings: _hideFolderHeadings,
    );
    setState(() {
      _hideReadChannels = hideReadChannels ?? _hideReadChannels;
      _hideFolderHeadings = hideFolderHeadings ?? _hideFolderHeadings;
      _savingPreferences = true;
    });
    unawaited(_writePreferences(previous));
  }

  Future<void> _writePreferences(SidebarViewPreferences previous) async {
    try {
      await widget.preferencesRepository.write(
        widget.accountScopeId,
        SidebarViewPreferences(
          hideReadChannels: _hideReadChannels,
          hideFolderHeadings: _hideFolderHeadings,
        ),
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _hideReadChannels = previous.hideReadChannels;
        _hideFolderHeadings = previous.hideFolderHeadings;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(ChannelSidebarStrings.preferencesSaveFailed),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingPreferences = false);
    }
  }

  void _onSearchFocusChanged() => setState(() {});

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<SidebarSection> get _filteredSections {
    final String normalizedQuery = _query.trim().toLowerCase();
    if (normalizedQuery.isEmpty && !_hideReadChannels) {
      final List<SidebarSection> sections = widget.snapshot.sections;
      return sections.every(
            (SidebarSection section) => section.channels.isNotEmpty,
          )
          ? sections
          : sections
                .where((SidebarSection section) => section.channels.isNotEmpty)
                .toList(growable: false);
    }

    return widget.snapshot.sections
        .map((SidebarSection section) {
          final List<SidebarChannel> channels = section.channels
              .where(
                (SidebarChannel channel) =>
                    (!_hideReadChannels ||
                        section.favorites ||
                        channel.hasUnreadMention ||
                        (channel.isUnread &&
                            !channel.muted &&
                            !section.muted)) &&
                    channel.displayName.toLowerCase().contains(normalizedQuery),
              )
              .toList(growable: false);
          return SidebarSection(
            id: section.id,
            displayName: section.displayName,
            channels: channels,
            collapsed: section.collapsed,
            serverCategory: section.serverCategory,
            favorites: section.favorites,
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
    if (!_preferencesLoaded) {
      return const SizedBox.expand();
    }
    final List<SidebarSection> filteredSections = _filteredSections;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.showTeamHeader) _TeamHeader(team: widget.snapshot.team),
        if (widget.refreshStatus is OperationInProgress)
          const LinearProgressIndicator(minHeight: 2),
        if (widget.refreshStatus is OperationFailed)
          const MaterialBanner(
            content: Text(ChannelSidebarStrings.refreshFailed),
            actions: <Widget>[SizedBox.shrink()],
            padding: AppLayout.sidebarBannerPadding,
          ),
        Padding(
          padding: AppLayout.sidebarSearchPadding,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppLayout.sidebarRowMinHeight + AppSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('channel-search-field'),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(fontSize: 13),
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    autocorrect: false,
                    textInputAction: TextInputAction.search,
                    onChanged: _updateQuery,
                    onSubmitted: (_) => _searchFocusNode.unfocus(),
                    onTapOutside: (_) => _searchFocusNode.unfocus(),
                    decoration: InputDecoration(
                      hintText: ChannelSidebarStrings.searchHint,
                      filled: true,
                      fillColor: colors.surface,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      constraints: AppLayout.sidebarSearchConstraints,
                      prefixIcon: const Padding(
                        padding: AppLayout.sidebarSearchIconPadding,
                        child: Icon(Icons.search),
                      ),
                      prefixIconConstraints:
                          AppLayout.sidebarSearchPrefixIconConstraints,
                      prefix: const SizedBox(width: AppSpacing.md),
                      suffixIcon: _hasSearchText
                          ? Transform.translate(
                              offset: const Offset(-AppSpacing.md, 0),
                              child: IconButton(
                                tooltip: ChannelSidebarStrings.clearSearch,
                                onPressed: _clearSearch,
                                icon: const Icon(Icons.close),
                              ),
                            )
                          : null,
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.outlineVariant),
                        borderRadius: BorderRadius.circular(AppSpacing.sm),
                        gapPadding: 0,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.primary, width: 2),
                        borderRadius: BorderRadius.circular(AppSpacing.sm),
                        gapPadding: 0,
                      ),
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.centerRight,
                  child: _searchFocusNode.hasFocus
                      ? const SizedBox.shrink()
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.only(
                                left: AppSpacing.xs,
                              ),
                              child: IconButton(
                                key: const ValueKey<String>(
                                  'read-channel-filter',
                                ),
                                tooltip: _hideReadChannels
                                    ? ChannelSidebarStrings.showReadChannels
                                    : ChannelSidebarStrings.hideReadChannels,
                                onPressed: _savingPreferences
                                    ? null
                                    : () => _savePreferences(
                                        hideReadChannels: !_hideReadChannels,
                                      ),
                                icon: Icon(
                                  _hideReadChannels
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 20,
                                  color: _hideReadChannels
                                      ? colors.primary.withValues(alpha: 0.7)
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            IconButton(
                              key: const ValueKey<String>(
                                'folder-visibility-toggle',
                              ),
                              tooltip: _hideFolderHeadings
                                  ? ChannelSidebarStrings.showFolderHeadings
                                  : ChannelSidebarStrings.hideFolderHeadings,
                              onPressed: _savingPreferences
                                  ? null
                                  : () => _savePreferences(
                                      hideFolderHeadings: !_hideFolderHeadings,
                                    ),
                              icon: Icon(
                                _hideFolderHeadings
                                    ? Icons.folder_outlined
                                    : Icons.folder_off_outlined,
                                size: 20,
                                color: _hideFolderHeadings
                                    ? colors.primary.withValues(alpha: 0.7)
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
        if (!_hasSearchQuery)
          _ThreadsTile(
            selected: widget.threadsSelected,
            unread: widget.threadsUnread,
            onTap: widget.onThreadsSelected,
          ),
        Expanded(
          child: filteredSections.isEmpty
              ? Center(
                  child: Text(
                    _hasSearchQuery
                        ? ChannelSidebarStrings.noSearchResults
                        : _hideReadChannels
                        ? ChannelSidebarStrings.noUnreadChannels
                        : ChannelSidebarStrings.empty,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  child: _LazyChannelList(
                    sections: filteredSections,
                    expandSections: _hasSearchQuery,
                    hideFolderHeadings: _hideFolderHeadings,
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

class _ThreadsTile extends StatelessWidget {
  const _ThreadsTile({
    required this.selected,
    required this.unread,
    required this.onTap,
  });

  final bool selected;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppLayout.sidebarItemInset,
      ),
      child: Material(
        key: const ValueKey<String>('threads-sidebar-tile'),
        color: selected ? colors.secondaryContainer : Colors.transparent,
        shape: _sidebarTileShape,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal:
                AppLayout.sidebarLeadingIconInset - AppLayout.sidebarItemInset,
          ),
          minTileHeight: AppLayout.sidebarRowMinHeight,
          minVerticalPadding: AppSpacing.xs,
          selected: selected,
          shape: _sidebarTileShape,
          leading: Icon(
            Icons.forum_outlined,
            size: 16,
            color: selected
                ? colors.onSecondaryContainer
                : colors.onSurfaceVariant,
          ),
          title: Text(
            ChannelSidebarStrings.threads,
            semanticsLabel: unread
                ? ChannelSidebarStrings.unreadChannel(
                    ChannelSidebarStrings.threads,
                  )
                : ChannelSidebarStrings.threads,
            style: theme.textTheme.bodyMedium!.copyWith(
              fontSize: 13,
              fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _TeamHeader extends StatelessWidget {
  const _TeamHeader({required this.team});

  final SidebarTeam? team;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(
      team?.displayName ?? ChannelSidebarStrings.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleMedium,
    ),
  );
}

class _LazyChannelList extends ConsumerStatefulWidget {
  const _LazyChannelList({
    required this.sections,
    required this.expandSections,
    required this.hideFolderHeadings,
    required this.onChannelSelected,
  });

  final List<SidebarSection> sections;
  final bool expandSections;
  final bool hideFolderHeadings;
  final VoidCallback? onChannelSelected;

  @override
  ConsumerState<_LazyChannelList> createState() => _LazyChannelListState();
}

class _LazyChannelListState extends ConsumerState<_LazyChannelList> {
  static const String _pageStorageIdentifier = 'collapsed-channel-sections';

  final Set<String> _collapsedSectionIds = <String>{};
  final Set<String> _initializedSectionIds = <String>{};
  bool _restoredFromPageStorage = false;
  final Set<String> _savingSectionIds = <String>{};
  final Set<String> _unsyncedSectionIds = <String>{};
  final Map<String, bool> _pendingSectionStates = <String, bool>{};

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
    if (storedIds case <String, Object?>{'unsynced': final List<Object?> ids}) {
      _unsyncedSectionIds.addAll(ids.whereType<String>());
    }
    for (final SidebarSection section in widget.sections) {
      if (section.serverCategory && !_unsyncedSectionIds.contains(section.id)) {
        _initializedSectionIds.remove(section.id);
        _collapsedSectionIds.remove(section.id);
      }
    }
    _applyServerDefaults();
  }

  @override
  void didUpdateWidget(_LazyChannelList oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final SidebarSection section in widget.sections) {
      final SidebarSection? old = oldWidget.sections
          .where((SidebarSection item) => item.id == section.id)
          .firstOrNull;
      if (old != null &&
          old.collapsed != section.collapsed &&
          !_savingSectionIds.contains(section.id) &&
          !_unsyncedSectionIds.contains(section.id)) {
        if (section.collapsed) {
          _collapsedSectionIds.add(section.id);
        } else {
          _collapsedSectionIds.remove(section.id);
        }
      }
    }
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
    final Set<String> collapsedSectionIds =
        widget.expandSections || widget.hideFolderHeadings
        ? const <String>{}
        : _collapsedSectionIds;
    final String? selectedChannelId = ref.watch(
      selectedChannelProvider.select((SidebarChannel? channel) => channel?.id),
    );
    final _ChannelListIndex index = _ChannelListIndex(
      selectedChannelId: selectedChannelId,
      sections: widget.sections,
      collapsedSectionIds: collapsedSectionIds,
      hideFolderHeadings: widget.hideFolderHeadings,
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
            onTap: widget.expandSections ? null : () => _toggleSection(section),
          );
        }
        final SidebarChannel channel = section.channels[row.channelIndex!];
        return _ChannelTile(
          key: ValueKey<String>('channel-${channel.id}'),
          channel: channel,
          favorite: section.favorites,
          muted: section.muted || channel.muted,
          selected: selectedChannelId == channel.id,
          onTap: () => _selectChannel(channel),
          onContextMenu: (Offset position) =>
              unawaited(_showChannelMenu(channel, section, position)),
        );
      },
    );
  }

  Future<void> _showChannelMenu(
    SidebarChannel channel,
    SidebarSection section,
    Offset position,
  ) async {
    final bool muted = section.muted || channel.muted;
    final _ChannelMenuAction? action = await showMenu<_ChannelMenuAction>(
      context: context,
      position: _menuPosition(position),
      constraints: const BoxConstraints(minWidth: 235, maxWidth: 290),
      items: <PopupMenuEntry<_ChannelMenuAction>>[
        _channelMenuItem(
          _ChannelMenuAction.unread,
          Icons.mark_chat_unread_outlined,
          ChannelSidebarStrings.markUnread,
        ),
        _channelMenuItem(
          _ChannelMenuAction.favorite,
          section.favorites ? Icons.star_outline : Icons.star_border,
          section.favorites
              ? ChannelSidebarStrings.removeFavorite
              : ChannelSidebarStrings.addFavorite,
        ),
        _channelMenuItem(
          _ChannelMenuAction.mute,
          muted
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          muted
              ? ChannelSidebarStrings.unmuteChannel
              : ChannelSidebarStrings.muteChannel,
        ),
        const PopupMenuDivider(),
        _channelMenuItem(
          _ChannelMenuAction.move,
          Icons.drive_file_move_outline,
          ChannelSidebarStrings.moveTo,
          trailing: Icons.chevron_right,
        ),
        if (channel.isDialog ||
            channel.name !=
                'town-square') ...<PopupMenuEntry<_ChannelMenuAction>>[
          const PopupMenuDivider(),
          if (channel.isDialog)
            _channelMenuItem(
              _ChannelMenuAction.close,
              Icons.logout,
              ChannelSidebarStrings.closeConversation,
              destructive: true,
            )
          else
            _channelMenuItem(
              _ChannelMenuAction.leave,
              Icons.logout,
              ChannelSidebarStrings.leaveChannel,
              destructive: true,
            ),
        ],
      ],
    );
    if (!mounted || action == null) return;
    final ChannelSidebarController controller = ref.read(
      channelSidebarProvider.notifier,
    );
    try {
      switch (action) {
        case _ChannelMenuAction.unread:
          await controller.markChannelUnread(channel.id);
        case _ChannelMenuAction.favorite:
          await controller.setChannelFavorite(channel, !section.favorites);
        case _ChannelMenuAction.mute:
          await controller.setChannelMuted(channel.id, !muted);
        case _ChannelMenuAction.move:
          final List<SidebarSection> categories = await controller
              .getMovableCategories();
          if (!mounted) return;
          final String? categoryId = await showMenu<String>(
            context: context,
            position: _menuPosition(position),
            constraints: const BoxConstraints(minWidth: 210, maxWidth: 280),
            items: <PopupMenuEntry<String>>[
              for (final SidebarSection category in categories)
                PopupMenuItem<String>(
                  value: category.id,
                  child: Row(
                    children: <Widget>[
                      if (category.id == section.id)
                        const Icon(Icons.check, size: 18)
                      else
                        const SizedBox(width: 18),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(category.displayName)),
                    ],
                  ),
                ),
            ],
          );
          if (categoryId != null && categoryId != section.id) {
            await controller.moveChannelToCategory(channel.id, categoryId);
          }
        case _ChannelMenuAction.close:
          await controller.closeConversation(channel);
        case _ChannelMenuAction.leave:
          final bool? confirmed = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) => AlertDialog(
              title: const Text(ChannelSidebarStrings.leaveChannelTitle),
              content: Text(
                channel.kind == ChannelKind.privateChannel
                    ? ChannelSidebarStrings.leavePrivateChannelDescription
                    : ChannelSidebarStrings.leaveChannelDescription,
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(ChannelSidebarStrings.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text(ChannelSidebarStrings.confirmLeaveChannel),
                ),
              ],
            ),
          );
          if (confirmed == true && mounted) {
            await controller.leaveChannel(channel);
          }
      }
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(ChannelSidebarStrings.channelActionFailed),
        ),
      );
    }
  }

  RelativeRect _menuPosition(Offset globalPosition) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final Offset position = overlay.globalToLocal(globalPosition);
    return RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 1, 1),
      Offset.zero & overlay.size,
    );
  }

  PopupMenuItem<_ChannelMenuAction> _channelMenuItem(
    _ChannelMenuAction action,
    IconData icon,
    String label, {
    IconData? trailing,
    bool destructive = false,
  }) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color color = destructive ? colors.error : colors.onSurfaceVariant;
    return PopupMenuItem<_ChannelMenuAction>(
      value: action,
      height: 44,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 19, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: destructive ? colors.error : null),
            ),
          ),
          if (trailing != null) Icon(trailing, size: 18, color: color),
        ],
      ),
    );
  }

  void _toggleSection(SidebarSection section) {
    final String sectionId = section.id;
    final bool collapsed = !_collapsedSectionIds.contains(sectionId);
    setState(() {
      if (collapsed) {
        _collapsedSectionIds.add(sectionId);
      } else {
        _collapsedSectionIds.remove(sectionId);
      }
      if (section.serverCategory) _unsyncedSectionIds.add(sectionId);
    });
    _saveExpansionState();
    if (!section.serverCategory) return;
    _pendingSectionStates[sectionId] = collapsed;
    if (_savingSectionIds.add(sectionId)) {
      unawaited(_syncSection(sectionId));
    }
  }

  Future<void> _syncSection(String sectionId) async {
    try {
      while (mounted && _pendingSectionStates.containsKey(sectionId)) {
        final bool collapsed = _pendingSectionStates.remove(sectionId)!;
        try {
          await ref
              .read(channelSidebarProvider.notifier)
              .setCategoryCollapsed(sectionId, collapsed);
          if (!mounted) return;
          if (!_pendingSectionStates.containsKey(sectionId)) {
            _unsyncedSectionIds.remove(sectionId);
            _saveExpansionState();
          }
        } on Object {
          if (!mounted) return;
          if (!_pendingSectionStates.containsKey(sectionId)) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text(ChannelSidebarStrings.categoryUpdateFailed),
              ),
            );
          }
        }
      }
    } finally {
      _savingSectionIds.remove(sectionId);
    }
  }

  void _saveExpansionState() {
    PageStorage.maybeOf(context)?.writeState(context, <String, Object?>{
      'collapsed': _collapsedSectionIds.toList(growable: false),
      'initialized': _initializedSectionIds.toList(growable: false),
      'unsynced': _unsyncedSectionIds.toList(growable: false),
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
    required String? selectedChannelId,
    required this.hideFolderHeadings,
  }) {
    var nextStart = 0;
    for (final SidebarSection section in sections) {
      _sectionStarts.add(nextStart);
      if (!hideFolderHeadings) nextStart += 1;
      final List<int> visible = <int>[
        for (final (int i, SidebarChannel channel) in section.channels.indexed)
          if (!collapsedSectionIds.contains(section.id) ||
              channel.hasUnreadMention ||
              (channel.isUnread && !channel.muted && !section.muted) ||
              channel.id == selectedChannelId)
            i,
      ];
      _visibleChannelIndices.add(visible);
      nextStart += visible.length;
    }
    rowCount = nextStart;
  }

  final List<SidebarSection> sections;
  final bool hideFolderHeadings;
  final List<int> _sectionStarts = <int>[];
  final List<List<int>> _visibleChannelIndices = <List<int>>[];
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
      channelIndex: hideFolderHeadings
          ? _visibleChannelIndices[low][offset]
          : offset == 0
          ? null
          : _visibleChannelIndices[low][offset - 1],
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppLayout.sidebarItemInset,
          AppSpacing.xs,
          AppLayout.sidebarItemInset,
          0,
        ),
        child: Material(
          key: ValueKey<String>('channel-section-surface-${section.id}'),
          color: Colors.transparent,
          shape: _sidebarTileShape,
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: AnimatedRotation(
              turns: isExpanded ? 0 : -0.25,
              duration: const Duration(milliseconds: 150),
              child: const Icon(Icons.expand_more, size: 14),
            ),
            title: Text(
              section.displayName.toUpperCase(),
              semanticsLabel: section.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            onTap: onTap,
            hoverColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            shape: _sidebarTileShape,
            dense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
            ),
            horizontalTitleGap: AppSpacing.xs,
            minLeadingWidth: 14,
            minTileHeight: AppLayout.sidebarRowMinHeight,
            minVerticalPadding: AppSpacing.xs,
          ),
        ),
      ),
    ),
  );
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required super.key,
    required this.channel,
    required this.favorite,
    required this.muted,
    required this.selected,
    required this.onTap,
    required this.onContextMenu,
  });

  final SidebarChannel channel;
  final bool favorite;
  final bool muted;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset> onContextMenu;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool highlightUnread =
        channel.hasUnreadMention || (channel.isUnread && !muted);
    void showKeyboardMenu() {
      final RenderBox? box = context.findRenderObject() as RenderBox?;
      if (box == null) return;
      onContextMenu(
        box.localToGlobal(Offset(box.size.width / 2, box.size.height)),
      );
    }

    return Focus(
      skipTraversal: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.contextMenu ||
                (event.logicalKey == LogicalKeyboardKey.f10 &&
                    HardwareKeyboard.instance.isShiftPressed))) {
          showKeyboardMenu();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (TapDownDetails details) =>
            onContextMenu(details.globalPosition),
        onLongPressStart: (LongPressStartDetails details) =>
            onContextMenu(details.globalPosition),
        child: Opacity(
          opacity: muted ? 0.55 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppLayout.sidebarItemInset,
            ),
            child: Material(
              key: ValueKey<String>('channel-selection-surface-${channel.id}'),
              color: selected ? colors.secondaryContainer : Colors.transparent,
              shape: _sidebarTileShape,
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal:
                      AppLayout.sidebarLeadingIconInset -
                      AppLayout.sidebarItemInset,
                ),
                minTileHeight: AppLayout.sidebarRowMinHeight,
                minVerticalPadding: AppSpacing.xs,
                horizontalTitleGap: AppSpacing.xs,
                minLeadingWidth: 20,
                selected: selected,
                shape: _sidebarTileShape,
                leading: IconTheme(
                  data: theme.iconTheme.copyWith(
                    color: selected
                        ? colors.onSecondaryContainer
                        : highlightUnread
                        ? colors.onSurface
                        : colors.onSurfaceVariant,
                  ),
                  child: ChannelAvatar(
                    channel: channel,
                    size: channel.kind == ChannelKind.directMessage ? 16 : 18,
                  ),
                ),
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        channel.displayName,
                        semanticsLabel: highlightUnread
                            ? ChannelSidebarStrings.unreadChannel(
                                channel.displayName,
                              )
                            : channel.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium!.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    if (favorite) ...<Widget>[
                      const SizedBox(width: AppSpacing.xs),
                      Icon(
                        Icons.star_rounded,
                        key: ValueKey<String>(
                          'channel-favorite-star-${channel.id}',
                        ),
                        size: 13,
                        color: colors.primary.withValues(alpha: 0.75),
                      ),
                    ],
                    if (highlightUnread) ...<Widget>[
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        key: ValueKey<String>(
                          'channel-unread-dot-${channel.id}',
                        ),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: selected
                              ? colors.onSecondaryContainer
                              : colors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                onTap: onTap,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
