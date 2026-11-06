import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/domain/models/auth_failure.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_controller.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_page.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_thread_host.dart';
import 'package:mattermost_flutter/src/features/profile/domain/models/current_user_profile.dart';
import 'package:mattermost_flutter/src/features/profile/presentation/profile_page.dart';
import 'package:mattermost_flutter/src/features/profile/presentation/widgets/profile_navigation_avatar.dart';
import 'package:mattermost_flutter/src/features/search/presentation/message_search_controller.dart';
import 'package:mattermost_flutter/src/features/search/presentation/message_search_page.dart';
import 'package:mattermost_flutter/src/ui/auth/auth_controller.dart';
import 'package:mattermost_flutter/src/ui/auth/auth_strings.dart';
import 'package:mattermost_flutter/src/ui/auth/widgets/sso_login_dialog.dart';
import 'package:mattermost_flutter/src/ui/channels/selected_channel_controller.dart';
import 'package:mattermost_flutter/src/ui/channels/widgets/channel_sidebar.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_breakpoints.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_spacing.dart';
import 'package:mattermost_flutter/src/ui/core/layout/resizable_pane_divider.dart';
import 'package:mattermost_flutter/src/ui/posts/channel_posts_strings.dart';
import 'package:mattermost_flutter/src/ui/posts/widgets/channel_posts_pane.dart';
import 'package:mattermost_flutter/src/ui/shell/shell_strings.dart';
import 'package:mattermost_flutter/src/ui/threads/widgets/followed_threads_pane.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

const Duration _inboxNotificationDuration = Duration(seconds: 5);

class BootstrapPage extends ConsumerStatefulWidget {
  const BootstrapPage({super.key});

  @override
  ConsumerState<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends ConsumerState<BootstrapPage>
    with WidgetsBindingObserver {
  bool _showCompactChannel = false;
  double _sidebarWidth = 280;
  late final ProviderSubscription<InboxInAppNotification?>
  _notificationSubscription;
  late final ProviderSubscription<bool> _channelPresentationSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationSubscription = ref.listenManual<InboxInAppNotification?>(
      inboxProvider.select(
        (AsyncValue<InboxViewState> value) => value.value?.inAppNotification,
      ),
      (InboxInAppNotification? previous, InboxInAppNotification? next) {
        if (next != null && previous?.id != next.id) {
          _showInboxNotification(next);
        }
      },
    );
    _channelPresentationSubscription = ref.listenManual<bool>(
      channelPresentationProvider,
      (bool? previous, bool next) {
        if (!next) return;
        _showSelectedChannelFromChannelsDestination();
        ref.read(channelPresentationProvider.notifier).markPresented();
      },
      fireImmediately: true,
    );
    unawaited(
      Future<void>(() => ref.read(authControllerProvider.notifier).restore()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSubscription.close();
    _channelPresentationSubscription.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(authControllerProvider).phase == AuthPhase.signedIn) {
      ref.read(realtimeConnectionServiceProvider).reconnect();
      ref.read(inboxProvider.notifier).handleAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(realtimeConnectionStatusProvider);
    final AuthState auth = ref.watch(authControllerProvider);
    if (auth.phase == AuthPhase.restoring) {
      return const _StartupContent();
    }
    if (auth.phase != AuthPhase.signedIn) {
      return _buildUnauthenticated(auth: auth);
    }
    final SidebarChannel? selectedChannel = ref.watch(selectedChannelProvider);
    final ShellDestination destination = ref.watch(shellDestinationProvider);
    final bool followedThreadsSelected =
        destination == ShellDestination.threads;
    final bool inboxSelected = destination == ShellDestination.inbox;
    final bool profileSelected = destination == ShellDestination.profile;
    final bool searchSelected = destination == ShellDestination.search;
    final ChannelSidebarSnapshot? sidebar = ref
        .watch(channelSidebarProvider)
        .value
        ?.snapshot;

    final bool inboxHasNewItems = ref.watch(
      inboxProvider.select((value) => value.value?.hasNewItems ?? false),
    );
    final CurrentUserProfile? currentUserProfile = ref
        .watch(currentUserProfileProvider)
        .value
        ?.profile;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < AppBreakpoints.compact) {
          return _buildCompact(
            auth: auth,
            selectedChannel: selectedChannel,
            followedThreadsSelected: followedThreadsSelected,
            inboxSelected: inboxSelected,
            sidebar: sidebar,
            inboxHasNewItems: inboxHasNewItems,
            currentUserProfile: currentUserProfile,
            profileSelected: profileSelected,
            searchSelected: searchSelected,
          );
        }
        return _buildDesktop(
          auth: auth,
          selectedChannel: selectedChannel,
          followedThreadsSelected: followedThreadsSelected,
          inboxSelected: inboxSelected,
          sidebar: sidebar,
          inboxHasNewItems: inboxHasNewItems,
          currentUserProfile: currentUserProfile,
          profileSelected: profileSelected,
          searchSelected: searchSelected,
          expanded: constraints.maxWidth >= AppBreakpoints.expanded,
        );
      },
    );
  }

  Widget _buildUnauthenticated({required AuthState auth}) =>
      Scaffold(body: _SignedOutContent(auth: auth));

  Widget _buildDesktop({
    required AuthState auth,
    required SidebarChannel? selectedChannel,
    required bool followedThreadsSelected,
    required bool inboxSelected,
    required ChannelSidebarSnapshot? sidebar,
    required bool inboxHasNewItems,
    required CurrentUserProfile? currentUserProfile,
    required bool profileSelected,
    required bool searchSelected,
    required bool expanded,
  }) {
    final bool inlineChannelHeader =
        selectedChannel != null &&
        !followedThreadsSelected &&
        !inboxSelected &&
        !profileSelected &&
        !searchSelected;
    final Widget mainContent = _MainContent(
      auth: auth,
      selectedChannel: selectedChannel,
      followedThreadsSelected: followedThreadsSelected,
      inboxSelected: false,
      sidebar: sidebar,
      onSelectChannel: _selectChannelNamed,
      onSearchInChannel: _openSearchInChannel,
      headerTrailing: inlineChannelHeader
          ? _HeaderProfileButton(
              profile: currentUserProfile,
              selected: false,
              onPressed: _showProfileDestination,
            )
          : null,
    );
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double maximumWidth = (constraints.maxWidth - 320).clamp(
              AppLayout.sidebarMinWidth,
              AppLayout.sidebarMaxWidth,
            );
            final double sidebarWidth = _sidebarWidth.clamp(
              AppLayout.sidebarMinWidth,
              maximumWidth,
            );
            final Widget channelWorkspace = Stack(
              children: <Widget>[
                Positioned.fill(
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        key: const ValueKey<String>('channels-side-pane'),
                        width: sidebarWidth,
                        child: Material(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          child: Column(
                            children: <Widget>[
                              if (inlineChannelHeader) ...<Widget>[
                                _DesktopSidebarHeader(
                                  height: 72,
                                  teamName: sidebar?.team?.displayName,
                                  channelsSelected: true,
                                  inboxSelected: false,
                                  inboxHasNewItems: inboxHasNewItems,
                                  onChannelsSelected: _showChannelsDestination,
                                  onInboxSelected: _showInboxDestination,
                                ),
                                const Divider(height: 1),
                              ],
                              Expanded(
                                child: ChannelSidebar(
                                  showTeamHeader: false,
                                  onChannelSelected: _showSelectedChannel,
                                  onThreadsSelected:
                                      _showFollowedThreadsDestination,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(child: mainContent),
                    ],
                  ),
                ),
                Positioned(
                  left: sidebarWidth - ResizablePaneDivider.width / 2,
                  top: 0,
                  bottom: 0,
                  child: ResizablePaneDivider(
                    key: const ValueKey<String>('channels-pane-divider'),
                    label: ShellStrings.resizeChannelsPane,
                    onResize: (double delta) => setState(() {
                      _sidebarWidth = (sidebarWidth + delta).clamp(
                        AppLayout.sidebarMinWidth,
                        maximumWidth,
                      );
                    }),
                  ),
                ),
              ],
            );
            return KeyedSubtree(
              key: ValueKey<String>(
                expanded ? 'expanded-layout' : 'medium-layout',
              ),
              child: inlineChannelHeader
                  ? channelWorkspace
                  : Column(
                      children: <Widget>[
                        _DesktopHeader(
                          sidebarWidth: inboxSelected
                              ? AppLayout.sidePaneWidth
                              : sidebarWidth,
                          teamName: sidebar?.team?.displayName,
                          channelsSelected:
                              !inboxSelected &&
                              !searchSelected &&
                              !profileSelected,
                          inboxSelected: inboxSelected,
                          inboxHasNewItems: inboxHasNewItems,
                          profile: currentUserProfile,
                          profileSelected: profileSelected,
                          onChannelsSelected: _showChannelsDestination,
                          onInboxSelected: _showInboxDestination,
                          onSearchSelected: _showSearchDestination,
                          onProfileSelected: _showProfileDestination,
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: profileSelected
                              ? ProfilePage(
                                  onLogout: () => ref
                                      .read(authControllerProvider.notifier)
                                      .signOut(),
                                )
                              : searchSelected
                              ? MessageSearchPage(
                                  launchIntent:
                                      ref.watch(searchLaunchIntentProvider)
                                          as SearchLaunchIntent?,
                                )
                              : inboxSelected
                              ? InboxThreadHost(
                                  inboxBuilder:
                                      (
                                        BuildContext context,
                                        ValueChanged<InboxItem> onOpenItem,
                                      ) => InboxPage(onOpenItem: onOpenItem),
                                  background: mainContent,
                                  showAdjacentWorkspace: true,
                                  onSelectChannel: _selectChannelNamed,
                                )
                              : channelWorkspace,
                        ),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCompact({
    required AuthState auth,
    required SidebarChannel? selectedChannel,
    required bool followedThreadsSelected,
    required bool inboxSelected,
    required ChannelSidebarSnapshot? sidebar,
    required bool inboxHasNewItems,
    required CurrentUserProfile? currentUserProfile,
    required bool profileSelected,
    required bool searchSelected,
  }) {
    final bool showChannel =
        _showCompactChannel &&
        !followedThreadsSelected &&
        !inboxSelected &&
        !searchSelected &&
        !profileSelected &&
        selectedChannel != null;
    final Widget pane;
    if (profileSelected) {
      pane = ProfilePage(
        onLogout: () => ref.read(authControllerProvider.notifier).signOut(),
      );
    } else if (showChannel) {
      pane = _MainContent(
        auth: auth,
        selectedChannel: selectedChannel,
        followedThreadsSelected: false,
        inboxSelected: false,
        sidebar: sidebar,
        onSelectChannel: _selectChannelNamed,
        onSearchInChannel: _openSearchInChannel,
        onBackToChannels: _showChannelsDestination,
      );
    } else if (searchSelected) {
      pane = MessageSearchPage(
        launchIntent:
            ref.watch(searchLaunchIntentProvider) as SearchLaunchIntent?,
      );
    } else if (inboxSelected) {
      pane = _MainContent(
        auth: auth,
        selectedChannel: selectedChannel,
        followedThreadsSelected: false,
        inboxSelected: true,
        sidebar: sidebar,
        onSelectChannel: _selectChannelNamed,
        onSearchInChannel: _openSearchInChannel,
      );
    } else if (followedThreadsSelected) {
      pane = _MainContent(
        auth: auth,
        selectedChannel: selectedChannel,
        followedThreadsSelected: true,
        inboxSelected: false,
        sidebar: sidebar,
        onSelectChannel: _selectChannelNamed,
        onSearchInChannel: _openSearchInChannel,
        onBackToChannels: _showChannelsDestination,
      );
    } else {
      pane = ChannelSidebar(
        onChannelSelected: _showSelectedChannel,
        onThreadsSelected: _showFollowedThreadsDestination,
      );
    }

    final bool showStackedContent = showChannel || followedThreadsSelected;

    return PopScope<void>(
      canPop: !showStackedContent,
      onPopInvokedWithResult: (bool didPop, void result) {
        if (!didPop && showStackedContent) _showChannelsDestination();
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (showStackedContent) _showChannelsDestination();
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            key: const ValueKey<String>('compact-layout'),
            body: SafeArea(child: pane),
            bottomNavigationBar: showStackedContent
                ? null
                : _BottomDestinations(
                    selectedIndex: profileSelected
                        ? 3
                        : searchSelected
                        ? 2
                        : inboxSelected
                        ? 1
                        : 0,
                    inboxHasNewItems: inboxHasNewItems,
                    profile: currentUserProfile,
                    onDestinationSelected: _selectDestination,
                  ),
          ),
        ),
      ),
    );
  }

  void _selectDestination(int index) {
    if (index == 3) {
      _showProfileDestination();
    } else if (index == 2) {
      _showSearchDestination();
    } else if (index == 1) {
      _showInboxDestination();
    } else {
      _showChannelsDestination();
    }
  }

  void _showChannelsDestination() {
    ref
        .read(shellDestinationProvider.notifier)
        .select(ShellDestination.channels);
    if (_showCompactChannel) {
      setState(() => _showCompactChannel = false);
    }
  }

  void _showInboxDestination() {
    ref.read(shellDestinationProvider.notifier).select(ShellDestination.inbox);
    if (_showCompactChannel) {
      setState(() => _showCompactChannel = false);
    }
  }

  void _showFollowedThreadsDestination() {
    ref
        .read(shellDestinationProvider.notifier)
        .select(ShellDestination.threads);
    if (_showCompactChannel) {
      setState(() => _showCompactChannel = false);
    }
  }

  void _showProfileDestination() {
    ref
        .read(shellDestinationProvider.notifier)
        .select(ShellDestination.profile);
    unawaited(ref.read(currentUserProfileProvider.notifier).refresh());
    if (_showCompactChannel) setState(() => _showCompactChannel = false);
  }

  void _showSearchDestination() {
    ref.read(shellDestinationProvider.notifier).select(ShellDestination.search);
    if (_showCompactChannel) setState(() => _showCompactChannel = false);
  }

  void _showInboxNotification(InboxInAppNotification notification) {
    if (ref.read(shellDestinationProvider) == ShellDestination.inbox) return;
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey<String>('inbox-in-app-notification'),
          duration: _inboxNotificationDuration,
          persist: false,
          content: Text(
            ShellStrings.inboxNotification(
              author: notification.candidate.post.author.displayName,
              channel: notification.candidate.channel.displayName,
              message: notification.candidate.post.message,
            ),
          ),
          action: SnackBarAction(
            label: ShellStrings.openInbox,
            onPressed: _showInboxDestination,
          ),
        ),
      );
  }

  void _showSelectedChannel() {
    if (ref.read(shellDestinationProvider) == ShellDestination.profile ||
        !_showCompactChannel) {
      setState(() {
        _showCompactChannel = true;
      });
    }
  }

  void _showSelectedChannelFromChannelsDestination() {
    ref
        .read(shellDestinationProvider.notifier)
        .select(ShellDestination.channels);
    if (!_showCompactChannel) {
      setState(() {
        _showCompactChannel = true;
      });
    }
  }

  void _selectChannelNamed(String name) {
    final ChannelSidebarSnapshot? snapshot = ref
        .read(channelSidebarProvider)
        .value
        ?.snapshot;
    if (snapshot == null) return;
    for (final SidebarSection section in snapshot.sections) {
      for (final SidebarChannel channel in section.channels) {
        if (channel.name == name) {
          ref
              .read(shellDestinationProvider.notifier)
              .select(ShellDestination.channels);
          ref.read(selectedChannelProvider.notifier).select(channel);
          _showSelectedChannel();
          return;
        }
      }
    }
  }

  void _openSearchInChannel(SidebarChannel channel) {
    final String token = switch (channel.kind) {
      ChannelKind.publicChannel || ChannelKind.privateChannel => channel.name,
      ChannelKind.directMessage || ChannelKind.groupMessage => '',
    };
    final String query = token.isEmpty ? 'in:' : 'in:$token ';
    final String? teamId = ref
        .read(channelSidebarProvider)
        .value
        ?.snapshot
        .team
        ?.id;
    if (teamId == null) return;
    ref
        .read(searchLaunchIntentProvider.notifier)
        .launch(
          SearchLaunchIntent(
            teamId: teamId,
            initialQuery: query,
            focus: true,
            nonce: Object(),
            replacesSearch: true,
          ),
        );
    _showSearchDestination();
  }
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({
    required this.sidebarWidth,
    required this.teamName,
    required this.channelsSelected,
    required this.inboxSelected,
    required this.inboxHasNewItems,
    required this.profile,
    required this.profileSelected,
    required this.onChannelsSelected,
    required this.onInboxSelected,
    required this.onSearchSelected,
    required this.onProfileSelected,
  });

  final double sidebarWidth;
  final String? teamName;
  final bool channelsSelected;
  final bool inboxSelected;
  final bool inboxHasNewItems;
  final CurrentUserProfile? profile;
  final bool profileSelected;
  final VoidCallback onChannelsSelected;
  final VoidCallback onInboxSelected;
  final VoidCallback onSearchSelected;
  final VoidCallback onProfileSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      child: SizedBox(
        height: 56,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: sidebarWidth,
              child: _DesktopSidebarHeader(
                height: 56,
                teamName: teamName,
                channelsSelected: channelsSelected,
                inboxSelected: inboxSelected,
                inboxHasNewItems: inboxHasNewItems,
                onChannelsSelected: onChannelsSelected,
                onInboxSelected: onInboxSelected,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  IconButton(
                    key: const ValueKey<String>('shell-search-destination'),
                    tooltip: ShellStrings.search,
                    onPressed: onSearchSelected,
                    icon: const Icon(Icons.search_outlined),
                  ),
                  _HeaderProfileButton(
                    profile: profile,
                    selected: profileSelected,
                    onPressed: onProfileSelected,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopSidebarHeader extends StatelessWidget {
  const _DesktopSidebarHeader({
    required this.height,
    required this.teamName,
    required this.channelsSelected,
    required this.inboxSelected,
    required this.inboxHasNewItems,
    required this.onChannelsSelected,
    required this.onInboxSelected,
  });

  final double height;
  final String? teamName;
  final bool channelsSelected;
  final bool inboxSelected;
  final bool inboxHasNewItems;
  final VoidCallback onChannelsSelected;
  final VoidCallback onInboxSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          _DestinationIcon(
            key: const ValueKey<String>('shell-channels-destination'),
            tooltip: ShellStrings.channels,
            selected: channelsSelected,
            onPressed: onChannelsSelected,
            icon: const Icon(Icons.tag_outlined),
          ),
          _DestinationIcon(
            key: const ValueKey<String>('shell-inbox-destination'),
            tooltip: inboxHasNewItems
                ? ShellStrings.inboxHasNewMessages
                : ShellStrings.inbox,
            selected: inboxSelected,
            onPressed: onInboxSelected,
            icon: _InboxNavigationIcon(hasNewItems: inboxHasNewItems),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              teamName ?? ShellStrings.channels,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    ),
  );
}

class _HeaderProfileButton extends StatelessWidget {
  const _HeaderProfileButton({
    required this.profile,
    required this.selected,
    required this.onPressed,
  });

  final CurrentUserProfile? profile;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey<String>('shell-profile-destination'),
    tooltip: ShellStrings.profile,
    isSelected: selected,
    onPressed: onPressed,
    icon: ProfileNavigationAvatar(profile: profile),
  );
}

class _DestinationIcon extends StatelessWidget {
  const _DestinationIcon({
    required this.tooltip,
    required this.selected,
    required this.onPressed,
    required this.icon,
    super.key,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: selected ? colors.secondaryContainer : null,
          foregroundColor: selected ? colors.onSecondaryContainer : null,
        ),
        icon: icon,
      ),
    );
  }
}

class _BottomDestinations extends StatelessWidget {
  const _BottomDestinations({
    required this.selectedIndex,
    required this.inboxHasNewItems,
    required this.profile,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final bool inboxHasNewItems;
  final CurrentUserProfile? profile;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) => NavigationBar(
    key: const ValueKey<String>('shell-bottom-navigation'),
    selectedIndex: selectedIndex,
    onDestinationSelected: onDestinationSelected,
    destinations: <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: ShellStrings.channels,
      ),
      NavigationDestination(
        icon: _InboxNavigationIcon(hasNewItems: inboxHasNewItems),
        selectedIcon: _InboxNavigationIcon(hasNewItems: inboxHasNewItems),
        label: ShellStrings.inbox,
      ),
      const NavigationDestination(
        icon: Icon(Icons.search_outlined),
        selectedIcon: Icon(Icons.search),
        label: ShellStrings.search,
      ),
      NavigationDestination(
        icon: ProfileNavigationAvatar(profile: profile),
        selectedIcon: ProfileNavigationAvatar(profile: profile),
        label: ShellStrings.profile,
      ),
    ],
  );
}

class _InboxNavigationIcon extends StatelessWidget {
  const _InboxNavigationIcon({required this.hasNewItems});

  final bool hasNewItems;

  @override
  Widget build(BuildContext context) => Semantics(
    label: hasNewItems ? ShellStrings.inboxHasNewMessages : ShellStrings.inbox,
    child: Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        const Icon(Icons.inbox_outlined),
        if (hasNewItems)
          PositionedDirectional(
            top: -2,
            end: -2,
            child: Container(
              key: const ValueKey<String>('inbox-navigation-indicator'),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    ),
  );
}

class _MainContent extends StatelessWidget {
  const _MainContent({
    required this.auth,
    required this.selectedChannel,
    required this.followedThreadsSelected,
    required this.inboxSelected,
    required this.sidebar,
    required this.onSelectChannel,
    required this.onSearchInChannel,
    this.onBackToChannels,
    this.headerTrailing,
  });

  final AuthState auth;
  final SidebarChannel? selectedChannel;
  final bool followedThreadsSelected;
  final bool inboxSelected;
  final ChannelSidebarSnapshot? sidebar;
  final ValueChanged<String> onSelectChannel;
  final ValueChanged<SidebarChannel> onSearchInChannel;
  final VoidCallback? onBackToChannels;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    if (auth.phase == AuthPhase.restoring) {
      return const Center(child: CircularProgressIndicator());
    }
    if (auth.phase == AuthPhase.signedIn) {
      if (inboxSelected && sidebar?.team != null) {
        return InboxThreadHost(
          inboxBuilder:
              (BuildContext context, ValueChanged<InboxItem> onOpenItem) =>
                  InboxPage(onOpenItem: onOpenItem),
          background: const SizedBox.shrink(),
          showAdjacentWorkspace: false,
          onSelectChannel: onSelectChannel,
        );
      }
      final SidebarTeam? team = sidebar?.team;
      if (followedThreadsSelected && team != null) {
        return FollowedThreadsPane(
          team: team,
          channelsById: <String, SidebarChannel>{
            for (final SidebarSection section in sidebar!.sections)
              for (final SidebarChannel channel in section.channels)
                channel.id: channel,
          },
          onSelectChannel: onSelectChannel,
          onBack: onBackToChannels,
        );
      }
      if (selectedChannel case final SidebarChannel channel) {
        return ChannelPostsPane(
          channel: channel,
          onSelectChannel: onSelectChannel,
          onBack: onBackToChannels,
          onSearchInChannel: onSearchInChannel,
          headerTrailing: headerTrailing,
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(ChannelPostsStrings.selectChannel),
            const SizedBox(height: 8),
            Text('${auth.session!.username} · ${auth.session!.serverUrl.host}'),
            const SizedBox(height: 20),
            Consumer(
              builder: (BuildContext context, WidgetRef ref, Widget? child) {
                return OutlinedButton(
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).signOut(),
                  child: const Text(AuthStrings.signOut),
                );
              },
            ),
          ],
        ),
      );
    }
    return _SignedOutContent(auth: auth);
  }
}

class _StartupContent extends StatelessWidget {
  const _StartupContent();

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey<String>('app-startup'),
    body: Center(
      child: CircularProgressIndicator(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _SignedOutContent extends ConsumerWidget {
  const _SignedOutContent({required this.auth});

  final AuthState auth;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (auth.failure != null) ...<Widget>[
            Text(
              _failureMessage(auth.failure!),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (BuildContext context) => const SsoLoginDialog(),
            ),
            icon: const Icon(Icons.login),
            label: const Text(AuthStrings.title),
          ),
          if (auth.failure == AuthFailureKind.network) ...<Widget>[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => unawaited(
                ref.read(authControllerProvider.notifier).restore(),
              ),
              child: const Text(AuthStrings.retry),
            ),
          ],
        ],
      ),
    ),
  );

  String _failureMessage(AuthFailureKind failure) => switch (failure) {
    AuthFailureKind.invalidCredentials ||
    AuthFailureKind.sessionExpired => AuthStrings.sessionExpired,
    AuthFailureKind.network => AuthStrings.restoreFailed,
    AuthFailureKind.storage => AuthStrings.storageError,
    AuthFailureKind.invalidServer => AuthStrings.invalidInput,
    AuthFailureKind.insecureProtocol => AuthStrings.insecureProtocol,
    AuthFailureKind.ssoUnavailable => AuthStrings.ssoUnavailable,
    AuthFailureKind.browserUnavailable => AuthStrings.browserUnavailable,
    AuthFailureKind.cancelled => '',
    AuthFailureKind.ssoFailed ||
    AuthFailureKind.tokenMissing ||
    AuthFailureKind.credentialsMissing ||
    AuthFailureKind.invalidResponse => AuthStrings.ssoFailed,
  };
}
