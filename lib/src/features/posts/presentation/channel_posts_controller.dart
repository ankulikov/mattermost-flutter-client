import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/features/posts/data/in_memory_channel_post_repository.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post_repository.dart';

final Provider<ChannelPostRepository> channelPostRepositoryProvider =
    Provider<ChannelPostRepository>(
      (Ref ref) => const InMemoryChannelPostRepository(),
    );

final channelPostsProvider = FutureProvider.family<List<ChannelPost>, String>((
  Ref ref,
  String channelId,
) {
  return ref.watch(channelPostRepositoryProvider).loadHistory(channelId);
});
