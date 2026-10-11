import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/channel_members/domain/channel_member.dart';
import 'package:mattermost_flutter/src/features/channel_members/presentation/channel_members_controller.dart';
import 'package:mattermost_flutter/src/features/channel_members/presentation/channel_members_providers.dart';
import 'package:mattermost_flutter/src/features/channel_members/presentation/channel_members_strings.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';
import 'package:mattermost_flutter/src/ui/users/widgets/user_avatar_image.dart';
import 'package:mattermost_flutter/src/ui/users/widgets/user_profile_card.dart';

class ChannelMembersPane extends ConsumerWidget {
  const ChannelMembersPane({
    required this.channel,
    required this.onClose,
    super.key,
  });

  final SidebarChannel channel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ChannelMembersViewState> members = ref.watch(
      channelMembersProvider(channel.id),
    );
    final AsyncValue<int> count = ref.watch(
      channelMemberCountProvider(channel.id),
    );
    return Material(
      key: ValueKey<String>('channel-members-pane-${channel.id}'),
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MembersHeader(channelName: channel.displayName, onClose: onClose),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              count.when(
                data: ChannelMembersStrings.count,
                loading: () => ChannelMembersStrings.loading,
                error: (_, _) => ChannelMembersStrings.title,
              ),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: members.when(
              loading: () => Center(
                child: Semantics(
                  label: ChannelMembersStrings.loading,
                  child: const CircularProgressIndicator(),
                ),
              ),
              error: (_, _) => _MembersError(
                onRetry: () => ref
                    .read(channelMembersProvider(channel.id).notifier)
                    .retry(),
              ),
              data: (ChannelMembersViewState state) =>
                  _MembersList(channelId: channel.id, state: state),
            ),
          ),
        ],
      ),
    );
  }
}

class _MembersHeader extends StatelessWidget {
  const _MembersHeader({required this.channelName, required this.onClose});

  final String channelName;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  ChannelMembersStrings.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 1,
                height: 24,
                color: Theme.of(context).dividerColor,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  channelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: ChannelMembersStrings.close,
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}

class _MembersList extends ConsumerWidget {
  const _MembersList({required this.channelId, required this.state});

  final String channelId;
  final ChannelMembersViewState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.members.isEmpty) {
      return const Center(child: Text(ChannelMembersStrings.empty));
    }
    return Column(
      children: <Widget>[
        if (state.paginationStatus is OperationFailed)
          MaterialBanner(
            content: const Text(ChannelMembersStrings.paginationFailed),
            actions: <Widget>[
              TextButton(
                onPressed: () => ref
                    .read(channelMembersProvider(channelId).notifier)
                    .loadMore(),
                child: const Text(ChannelMembersStrings.retry),
              ),
            ],
          ),
        Expanded(
          child: ListView.builder(
            key: PageStorageKey<String>('channel-members-$channelId'),
            itemCount: state.members.length + (state.hasMore ? 1 : 0),
            itemBuilder: (BuildContext context, int index) {
              if (index == state.members.length) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: state.paginationStatus is OperationInProgress
                        ? const CircularProgressIndicator()
                        : OutlinedButton(
                            onPressed: () => ref
                                .read(
                                  channelMembersProvider(channelId).notifier,
                                )
                                .loadMore(),
                            child: const Text(ChannelMembersStrings.loadMore),
                          ),
                  ),
                );
              }
              return _MemberTile(member: state.members[index]);
            },
          ),
        ),
      ],
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.member});

  final ChannelMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = member.user;
    return ListTile(
      key: ValueKey<String>('channel-member-${user.id}'),
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      leading: UserAvatarImage(
        userId: user.id,
        displayName: user.fullName,
        profileImageUpdatedAt: user.profileImageUpdatedAt,
        radius: 12,
      ),
      title: Text(
        user.fullName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      trailing: member.isChannelAdmin
          ? const Tooltip(
              message: ChannelMembersStrings.channelAdmin,
              child: Icon(Icons.shield_outlined, size: 20),
            )
          : null,
      onTap: () => unawaited(
        showUserProfileCard(
          context,
          userId: user.id,
          onMessage: (UserProfile profile) =>
              _openDirectMessage(context, ref, profile),
        ),
      ),
    );
  }
}

Future<void> _openDirectMessage(
  BuildContext context,
  WidgetRef ref,
  UserProfile profile,
) async {
  await ref.read(channelSidebarProvider.notifier).openDirectMessage(profile);
  if (context.mounted) context.go('/');
}

class _MembersError extends StatelessWidget {
  const _MembersError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            ChannelMembersStrings.loadFailed,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text(ChannelMembersStrings.retry),
          ),
        ],
      ),
    ),
  );
}
