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
import 'package:mattermost_flutter/src/ui/posts/channel_posts_strings.dart';
import 'package:mattermost_flutter/src/ui/posts/widgets/channel_posts_pane.dart';
import 'package:mattermost_flutter/src/ui/shell/shell_strings.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

class BootstrapPage extends ConsumerStatefulWidget {
  const BootstrapPage({super.key});

  @override
  ConsumerState<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends ConsumerState<BootstrapPage>
    with WidgetsBindingObserver {
  bool _showCompactChannel = false;
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
      ref.read(inboxProvider.notifier).handleAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthState auth = ref.watch(authControllerProvider);
    final SidebarChannel? selectedChannel = ref.watch(selectedChannelProvider);
    final ShellDestination destination = ref.watch(shellDestinationProvider);
    final bool threadsSelected = destination == ShellDestination.inbox;
    final bool profileSelected = destination == ShellDestination.profile;
    final bool searchSelected = destination == ShellDestination.search;
    final ChannelSidebarSnapshot? sidebar = ref
        .watch(channelSidebarProvider)
        .value
        ?.snapshot;

    if (auth.phase != AuthPhase.signedIn) {
      return _buildUnauthenticated(
        auth: auth,
        selectedChannel: selectedChannel,
        threadsSelected: threadsSelected,
        sidebar: sidebar,
      );
    }
    final bool inboxHasNewItems = ref.watch(
      inboxProvider.select(
        (value) => value.value?.snapshot.hasNewItems ?? false,
      ),
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
            threadsSelected: threadsSelected,
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
          threadsSelected: threadsSelected,
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

  Widget _buildUnauthenticated({
    required AuthState auth,
    required SidebarChannel? selectedChannel,
    required bool threadsSelected,
    required ChannelSidebarSnapshot? sidebar,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool expanded = constraints.maxWidth >= AppBreakpoints.expanded;
        final Widget content = _MainContent(
          auth: auth,
          selectedChannel: selectedChannel,
          threadsSelected: threadsSelected,
          sidebar: sidebar,
          onSelectChannel: _selectChannelNamed,
          onSearchInChannel: _openSearchInChannel,
        );
        if (expanded) {
          return Scaffold(
            body: Row(
              children: <Widget>[
                const SizedBox(width: 280, child: ChannelSidebar()),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text(ShellStrings.appTitle)),
          body: content,
          drawer: const Drawer(child: ChannelSidebar()),
        );
      },
    );
  }

  Widget _buildDesktop({
    required AuthState auth,
    required SidebarChannel? selectedChannel,
    required bool threadsSelected,
    required ChannelSidebarSnapshot? sidebar,
    required bool inboxHasNewItems,
    required CurrentUserProfile? currentUserProfile,
    required bool profileSelected,
    required bool searchSelected,
    required bool expanded,
  }) {
    final Widget mainContent = _MainContent(
      auth: auth,
      selectedChannel: selectedChannel,
      threadsSelected: false,
      sidebar: sidebar,
      onSelectChannel: _selectChannelNamed,
      onSearchInChannel: _openSearchInChannel,
    );
    return Scaffold(
      body: SafeArea(
        child: Row(
          key: ValueKey<String>(expanded ? 'expanded-layout' : 'medium-layout'),
          children: <Widget>[
            _DestinationRail(
              selectedIndex: profileSelected
                  ? null
                  : searchSelected
                  ? 2
                  : threadsSelected
                  ? 1
                  : 0,
              inboxHasNewItems: inboxHasNewItems,
              profile: currentUserProfile,
              profileSelected: profileSelected,
              onDestinationSelected: _selectDestination,
              onProfileSelected: _showProfileDestination,
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: profileSelected
                  ? ProfilePage(
                      onLogout: () =>
                          ref.read(authControllerProvider.notifier).signOut(),
                    )
                  : searchSelected
                  ? MessageSearchPage(
                      launchIntent:
                          ref.watch(searchLaunchIntentProvider)
                              as SearchLaunchIntent?,
                    )
                  : threadsSelected
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
                  : Row(
                      children: <Widget>[
                        SizedBox(
                          key: ValueKey<String>('channels-side-pane'),
                          width: 280,
                          child: ChannelSidebar(
                            onChannelSelected: _showSelectedChannel,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: mainContent),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompact({
    required AuthState auth,
    required SidebarChannel? selectedChannel,
    required bool threadsSelected,
    required ChannelSidebarSnapshot? sidebar,
    required bool inboxHasNewItems,
    required CurrentUserProfile? currentUserProfile,
    required bool profileSelected,
    required bool searchSelected,
  }) {
    final bool showChannel =
        _showCompactChannel &&
        !threadsSelected &&
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
        threadsSelected: false,
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
    } else if (threadsSelected) {
      pane = _MainContent(
        auth: auth,
        selectedChannel: selectedChannel,
        threadsSelected: true,
        sidebar: sidebar,
        onSelectChannel: _selectChannelNamed,
        onSearchInChannel: _openSearchInChannel,
      );
    } else {
      pane = ChannelSidebar(onChannelSelected: _showSelectedChannel);
    }

    return PopScope<void>(
      canPop: !showChannel,
      onPopInvokedWithResult: (bool didPop, void result) {
        if (!didPop && showChannel) _showChannelsDestination();
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (showChannel) _showChannelsDestination();
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            key: const ValueKey<String>('compact-layout'),
            body: SafeArea(child: pane),
            bottomNavigationBar: showChannel
                ? null
                : _BottomDestinations(
                    selectedIndex: profileSelected
                        ? 3
                        : searchSelected
                        ? 2
                        : threadsSelected
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
      _showThreadsDestination();
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

  void _showThreadsDestination() {
    ref.read(shellDestinationProvider.notifier).select(ShellDestination.inbox);
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
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey<String>('inbox-in-app-notification'),
          content: Text(
            ShellStrings.inboxNotification(
              author: notification.candidate.post.author.displayName,
              channel: notification.candidate.channel.displayName,
              message: notification.candidate.post.message,
            ),
          ),
          action: SnackBarAction(
            label: ShellStrings.openInbox,
            onPressed: _showThreadsDestination,
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
          ),
        );
    _showSearchDestination();
  }
}

class _DestinationRail extends StatelessWidget {
  const _DestinationRail({
    required this.selectedIndex,
    required this.inboxHasNewItems,
    required this.profile,
    required this.profileSelected,
    required this.onDestinationSelected,
    required this.onProfileSelected,
  });

  final int? selectedIndex;
  final bool inboxHasNewItems;
  final CurrentUserProfile? profile;
  final bool profileSelected;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onProfileSelected;

  @override
  Widget build(BuildContext context) => NavigationRail(
    key: const ValueKey<String>('shell-navigation-rail'),
    selectedIndex: selectedIndex,
    labelType: NavigationRailLabelType.all,
    groupAlignment: -1,
    minWidth: 82,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    onDestinationSelected: onDestinationSelected,
    trailing: Expanded(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: _RailProfileDestination(
          profile: profile,
          selected: profileSelected,
          onPressed: onProfileSelected,
        ),
      ),
    ),
    destinations: <NavigationRailDestination>[
      const NavigationRailDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: Text(ShellStrings.channels),
      ),
      NavigationRailDestination(
        icon: _InboxNavigationIcon(hasNewItems: inboxHasNewItems),
        selectedIcon: _InboxNavigationIcon(hasNewItems: inboxHasNewItems),
        label: const Text(ShellStrings.inbox),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.search_outlined),
        selectedIcon: Icon(Icons.search),
        label: Text(ShellStrings.search),
      ),
    ],
  );
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

class _RailProfileDestination extends StatelessWidget {
  const _RailProfileDestination({
    required this.profile,
    required this.selected,
    required this.onPressed,
  });

  final CurrentUserProfile? profile;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Tooltip(
      message: ShellStrings.profile,
      child: InkWell(
        key: const ValueKey<String>('shell-profile-destination'),
        borderRadius: BorderRadius.circular(28),
        onTap: onPressed,
        child: Semantics(
          selected: selected,
          button: true,
          label: ShellStrings.profile,
          child: Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : null,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ProfileNavigationAvatar(profile: profile),
                const SizedBox(height: 3),
                Text(
                  ShellStrings.profile,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
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
        const Icon(Icons.forum_outlined),
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
    required this.threadsSelected,
    required this.sidebar,
    required this.onSelectChannel,
    required this.onSearchInChannel,
    this.onBackToChannels,
  });

  final AuthState auth;
  final SidebarChannel? selectedChannel;
  final bool threadsSelected;
  final ChannelSidebarSnapshot? sidebar;
  final ValueChanged<String> onSelectChannel;
  final ValueChanged<SidebarChannel> onSearchInChannel;
  final VoidCallback? onBackToChannels;

  @override
  Widget build(BuildContext context) {
    if (auth.phase == AuthPhase.restoring) {
      return const Center(child: CircularProgressIndicator());
    }
    if (auth.phase == AuthPhase.signedIn) {
      if (threadsSelected && sidebar?.team != null) {
        return InboxThreadHost(
          inboxBuilder:
              (BuildContext context, ValueChanged<InboxItem> onOpenItem) =>
                  InboxPage(onOpenItem: onOpenItem),
          background: const SizedBox.shrink(),
          showAdjacentWorkspace: false,
          onSelectChannel: onSelectChannel,
        );
      }
      if (selectedChannel case final SidebarChannel channel) {
        return ChannelPostsPane(
          channel: channel,
          onSelectChannel: onSelectChannel,
          onBack: onBackToChannels,
          onSearchInChannel: onSearchInChannel,
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
    AuthFailureKind.ssoUnavailable => AuthStrings.ssoUnavailable,
    AuthFailureKind.browserUnavailable => AuthStrings.browserUnavailable,
    AuthFailureKind.cancelled => '',
    AuthFailureKind.ssoFailed ||
    AuthFailureKind.tokenMissing ||
    AuthFailureKind.credentialsMissing ||
    AuthFailureKind.invalidResponse => AuthStrings.ssoFailed,
  };
}
