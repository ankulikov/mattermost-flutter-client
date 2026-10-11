import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/data/providers/repository_providers.dart';
import 'package:mattermost_flutter/src/features/channel_members/presentation/channel_members_controller.dart';

final channelMemberCountProvider = FutureProvider.autoDispose
    .family<int, String>((Ref ref, String channelId) {
      final RequestCancellation cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      return cancellation.run(
        () => ref.watch(channelMembersRepositoryProvider).getCount(channelId),
      );
    });

final channelMembersProvider = AsyncNotifierProvider.autoDispose
    .family<ChannelMembersController, ChannelMembersViewState, String>(
      (String channelId) =>
          ChannelMembersController(channelId, channelMembersRepositoryProvider),
    );
