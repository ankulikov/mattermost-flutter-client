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
    unawaited(
      Future<void>(() => ref.read(authControllerProvider.notifier).restore()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSubscription.close();
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
    final bool threadsSelected = ref.watch(threadsDestinationProvider);
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
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < AppBreakpoints.compact) {
          return _buildCompact(
            auth: auth,
            selectedChannel: selectedChannel,
            threadsSelected: threadsSelected,
            sidebar: sidebar,
            inboxHasNewItems: inboxHasNewItems,
          );
        }
        return _buildDesktop(
          auth: auth,
          selectedChannel: selectedChannel,
          threadsSelected: threadsSelected,
          sidebar: sidebar,
          inboxHasNewItems: inboxHasNewItems,
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
          onOpenChannel: _openInboxChannel,
          onSelectChannel: _selectChannelNamed,
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
    required bool expanded,
  }) {
    final Widget mainContent = _MainContent(
      auth: auth,
      selectedChannel: selectedChannel,
      threadsSelected: false,
      sidebar: sidebar,
      onOpenChannel: _openInboxChannel,
      onSelectChannel: _selectChannelNamed,
    );
    return Scaffold(
      body: SafeArea(
        child: Row(
          key: ValueKey<String>(expanded ? 'expanded-layout' : 'medium-layout'),
          children: <Widget>[
            _DestinationRail(
              selectedIndex: threadsSelected ? 1 : 0,
              inboxHasNewItems: inboxHasNewItems,
              onDestinationSelected: _selectDestination,
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: threadsSelected
                  ? InboxThreadHost(
                      inboxBuilder:
                          (
                            BuildContext context,
                            ValueChanged<InboxItem> onOpenItem,
                          ) => InboxPage(onOpenItem: onOpenItem),
                      background: mainContent,
                      showAdjacentThread: true,
                      onOpenChannel: _openInboxChannel,
                      onSelectChannel: _selectChannelNamed,
                    )
                  : Row(
                      children: <Widget>[
                        const SizedBox(
                          key: ValueKey<String>('channels-side-pane'),
                          width: 280,
                          child: ChannelSidebar(),
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
  }) {
    final bool showChannel =
        _showCompactChannel && !threadsSelected && selectedChannel != null;
    final Widget pane;
    if (showChannel) {
      pane = _MainContent(
        auth: auth,
        selectedChannel: selectedChannel,
        threadsSelected: false,
        sidebar: sidebar,
        onOpenChannel: _openInboxChannel,
        onSelectChannel: _selectChannelNamed,
        onBackToChannels: _showChannelsDestination,
      );
    } else if (threadsSelected) {
      pane = _MainContent(
        auth: auth,
        selectedChannel: selectedChannel,
        threadsSelected: true,
        sidebar: sidebar,
        onOpenChannel: _openInboxChannel,
        onSelectChannel: _selectChannelNamed,
      );
    } else {
      pane = ChannelSidebar(onChannelSelected: _showSelectedChannelOnCompact);
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
                    selectedIndex: threadsSelected ? 1 : 0,
                    inboxHasNewItems: inboxHasNewItems,
                    onDestinationSelected: _selectDestination,
                  ),
          ),
        ),
      ),
    );
  }

  void _selectDestination(int index) {
    if (index == 1) {
      _showThreadsDestination();
    } else {
      _showChannelsDestination();
    }
  }

  void _showChannelsDestination() {
    ref.read(threadsDestinationProvider.notifier).clear();
    if (_showCompactChannel) {
      setState(() => _showCompactChannel = false);
    }
  }

  void _showThreadsDestination() {
    ref.read(threadsDestinationProvider.notifier).select();
    if (_showCompactChannel) {
      setState(() => _showCompactChannel = false);
    }
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

  void _showSelectedChannelOnCompact() {
    if (!_showCompactChannel) {
      setState(() => _showCompactChannel = true);
    }
  }

  void _openInboxChannel(SidebarChannel channel) {
    ref.read(threadsDestinationProvider.notifier).clear();
    ref.read(selectedChannelProvider.notifier).select(channel);
    _showSelectedChannelOnCompact();
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
          ref.read(threadsDestinationProvider.notifier).clear();
          ref.read(selectedChannelProvider.notifier).select(channel);
          _showSelectedChannelOnCompact();
          return;
        }
      }
    }
  }
}

class _DestinationRail extends StatelessWidget {
  const _DestinationRail({
    required this.selectedIndex,
    required this.inboxHasNewItems,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final bool inboxHasNewItems;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) => NavigationRail(
    key: const ValueKey<String>('shell-navigation-rail'),
    selectedIndex: selectedIndex,
    labelType: NavigationRailLabelType.all,
    groupAlignment: -1,
    minWidth: 82,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    onDestinationSelected: onDestinationSelected,
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
    ],
  );
}

class _BottomDestinations extends StatelessWidget {
  const _BottomDestinations({
    required this.selectedIndex,
    required this.inboxHasNewItems,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final bool inboxHasNewItems;
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
    required this.onOpenChannel,
    required this.onSelectChannel,
    this.onBackToChannels,
  });

  final AuthState auth;
  final SidebarChannel? selectedChannel;
  final bool threadsSelected;
  final ChannelSidebarSnapshot? sidebar;
  final ValueChanged<SidebarChannel> onOpenChannel;
  final ValueChanged<String> onSelectChannel;
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
          showAdjacentThread: false,
          onOpenChannel: onOpenChannel,
          onSelectChannel: onSelectChannel,
        );
      }
      if (selectedChannel case final SidebarChannel channel) {
        return ChannelPostsPane(
          channel: channel,
          onSelectChannel: onSelectChannel,
          onBack: onBackToChannels,
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
