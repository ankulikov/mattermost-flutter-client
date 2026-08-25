import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/app/di/app_providers.dart';
import 'package:mattermost_flutter/src/core/ui/app_breakpoints.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/auth_controller.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/auth_strings.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/pat_login_dialog.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';
import 'package:mattermost_flutter/src/features/channels/presentation/channel_sidebar.dart';
import 'package:mattermost_flutter/src/features/channels/presentation/selected_channel_controller.dart';
import 'package:mattermost_flutter/src/features/posts/presentation/channel_posts_pane.dart';
import 'package:mattermost_flutter/src/features/posts/presentation/channel_posts_strings.dart';
import 'package:mattermost_flutter/src/features/threads/presentation/followed_threads_pane.dart';

class BootstrapPage extends ConsumerStatefulWidget {
  const BootstrapPage({super.key});

  @override
  ConsumerState<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends ConsumerState<BootstrapPage> {
  @override
  void initState() {
    super.initState();
    unawaited(
      Future<void>(() => ref.read(authControllerProvider.notifier).restore()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AuthState auth = ref.watch(authControllerProvider);
    final SidebarChannel? selectedChannel = ref.watch(selectedChannelProvider);
    final bool threadsSelected = ref.watch(threadsDestinationProvider);
    final ChannelSidebarSnapshot? sidebar = ref
        .watch(channelSidebarProvider)
        .value;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool expanded = constraints.maxWidth >= AppBreakpoints.expanded;
        if (expanded) {
          return Scaffold(
            body: Row(
              children: <Widget>[
                const SizedBox(width: 280, child: ChannelSidebar()),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _MainContent(
                    auth: auth,
                    selectedChannel: selectedChannel,
                    threadsSelected: threadsSelected,
                    sidebar: sidebar,
                    onSelectChannel: _selectChannelNamed,
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(
              threadsSelected
                  ? 'Threads'
                  : selectedChannel?.displayName ?? 'Mattermost',
            ),
          ),
          body: _MainContent(
            auth: auth,
            selectedChannel: selectedChannel,
            threadsSelected: threadsSelected,
            sidebar: sidebar,
            onSelectChannel: _selectChannelNamed,
          ),
          drawer: const Drawer(child: ChannelSidebar()),
        );
      },
    );
  }

  void _selectChannelNamed(String name) {
    final ChannelSidebarSnapshot? snapshot = ref
        .read(channelSidebarProvider)
        .value;
    if (snapshot == null) return;
    for (final SidebarSection section in snapshot.sections) {
      for (final SidebarChannel channel in section.channels) {
        if (channel.name == name) {
          ref.read(threadsDestinationProvider.notifier).clear();
          ref.read(selectedChannelProvider.notifier).select(channel);
          return;
        }
      }
    }
  }
}

class _MainContent extends StatelessWidget {
  const _MainContent({
    required this.auth,
    required this.selectedChannel,
    required this.threadsSelected,
    required this.sidebar,
    required this.onSelectChannel,
  });

  final AuthState auth;
  final SidebarChannel? selectedChannel;
  final bool threadsSelected;
  final ChannelSidebarSnapshot? sidebar;
  final ValueChanged<String> onSelectChannel;

  @override
  Widget build(BuildContext context) {
    if (auth.phase == AuthPhase.restoring) {
      return const Center(child: CircularProgressIndicator());
    }
    if (auth.phase == AuthPhase.signedIn) {
      if (threadsSelected && sidebar?.team != null) {
        final Map<String, SidebarChannel> channelsById =
            <String, SidebarChannel>{
              for (final SidebarSection section in sidebar!.sections)
                for (final SidebarChannel channel in section.channels)
                  channel.id: channel,
            };
        return FollowedThreadsPane(
          team: sidebar!.team!,
          channelsById: channelsById,
          onSelectChannel: onSelectChannel,
        );
      }
      if (selectedChannel case final SidebarChannel channel) {
        return ChannelPostsPane(
          channel: channel,
          onSelectChannel: onSelectChannel,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FilledButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (BuildContext context) => const PatLoginDialog(),
          ),
          icon: const Icon(Icons.key),
          label: const Text(AuthStrings.title),
        ),
      ),
    );
  }
}
