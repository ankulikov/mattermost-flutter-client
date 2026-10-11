import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/features/channel_members/presentation/channel_members_providers.dart';
import 'package:mattermost_flutter/src/features/channel_members/presentation/channel_members_strings.dart';

class ChannelMemberCountButton extends ConsumerWidget {
  const ChannelMemberCountButton({
    required this.channelId,
    required this.onPressed,
    super.key,
  });

  final String channelId;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<int> count = ref.watch(
      channelMemberCountProvider(channelId),
    );
    final String label = count.when(
      data: ChannelMembersStrings.count,
      loading: () => ChannelMembersStrings.title,
      error: (_, _) => ChannelMembersStrings.title,
    );
    final String visibleCount = count.when(
      data: (int value) => '$value',
      loading: () => '…',
      error: (_, _) => '!',
    );
    return Tooltip(
      message: label,
      child: TextButton.icon(
        key: ValueKey<String>('channel-member-count-$channelId'),
        onPressed: () {
          if (count.hasError) {
            ref.invalidate(channelMemberCountProvider(channelId));
          }
          onPressed();
        },
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: const Size(48, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        icon: const Icon(Icons.people_outline, size: 18),
        label: Text(visibleCount, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
