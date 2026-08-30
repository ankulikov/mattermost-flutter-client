import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/data/providers/repository_providers.dart';
import 'package:mattermost_flutter/src/domain/models/attachment.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/models/user_avatar.dart';
import 'package:mattermost_flutter/src/domain/models/user_mention.dart';
import 'package:mattermost_flutter/src/features/channels/presentation/channel_sidebar_controller.dart';
import 'package:mattermost_flutter/src/features/channels/presentation/selected_channel_controller.dart';
import 'package:mattermost_flutter/src/features/posts/presentation/channel_posts_controller.dart';
import 'package:mattermost_flutter/src/features/threads/presentation/followed_threads_controller.dart';
import 'package:mattermost_flutter/src/features/threads/presentation/thread_controller.dart';
import 'package:mattermost_flutter/src/ui/auth/auth_controller.dart';

export '../../data/providers/infrastructure_providers.dart';
export '../../data/providers/repository_providers.dart';
export '../../data/providers/session_providers.dart';

final NotifierProvider<AuthController, AuthState> authControllerProvider =
    NotifierProvider<AuthController, AuthState>(
      () => AuthController(authRepositoryProvider),
    );

/// UI projection for controller state. It contains only the domain session;
/// the active transport remains owned by data providers.
final Provider<AuthSession?> authSessionProvider = Provider<AuthSession?>((
  Ref ref,
) {
  return ref.watch(
    authControllerProvider.select((AuthState state) => state.session),
  );
});

typedef AttachmentContentRequest = ({String fileId, AttachmentVariant variant});

final attachmentContentProvider = FutureProvider.autoDispose
    .family<AttachmentContent, AttachmentContentRequest>((
      Ref ref,
      AttachmentContentRequest request,
    ) {
      final RequestCancellation cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      return cancellation.run(
        () => ref
            .watch(attachmentRepositoryProvider)
            .load(fileId: request.fileId, variant: request.variant),
      );
    });

typedef UserAvatarRequest = ({String userId, int profileImageUpdatedAt});

final userAvatarProvider = FutureProvider.autoDispose
    .family<UserAvatar?, UserAvatarRequest>((Ref ref, UserAvatarRequest input) {
      final AuthSession? session = ref.watch(authSessionProvider);
      if (session == null || input.userId.isEmpty) return null;
      return ref
          .watch(userRepositoryProvider)
          .loadAvatar(
            userId: input.userId,
            profileImageUpdatedAt: input.profileImageUpdatedAt,
          );
    });

final customEmojiProvider = FutureProvider.autoDispose
    .family<CustomEmojiContent, CustomEmojiReference>((
      Ref ref,
      CustomEmojiReference emoji,
    ) {
      final AuthSession? session = ref.watch(authSessionProvider);
      if (session == null) {
        throw StateError('No active Mattermost session');
      }
      return ref
          .watch(customEmojiRepositoryProvider)
          .getByName(
            accountId: session.durableDataScopeId,
            name: emoji.name,
            emojiId: emoji.id,
            updatedAt: emoji.updatedAt,
          );
    });

final userMentionsProvider = FutureProvider.autoDispose
    .family<List<UserMention>, String>((Ref ref, String lookupKey) {
      final List<String> usernames = lookupKey.isEmpty
          ? const <String>[]
          : lookupKey.split(',');
      if (usernames.isEmpty) return const <UserMention>[];
      final RequestCancellation cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      return cancellation.run(
        () async =>
            (await ref
                    .watch(userRepositoryProvider)
                    .resolveUsersByUsernames(usernames))
                .map(userMentionFromSummary)
                .toList(growable: false),
      );
    });

final userProfileProvider = FutureProvider.autoDispose
    .family<UserProfile, String>((Ref ref, String userId) {
      final RequestCancellation cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      return cancellation.run(
        () => ref.watch(userRepositoryProvider).getProfile(userId),
      );
    });

Future<void> openDirectMessage(WidgetRef ref, UserProfile profile) async {
  final AuthSession? session = ref.read(authSessionProvider);
  if (session == null) throw StateError('No active Mattermost session');
  final SidebarChannel channel = await ref
      .read(directChannelRepositoryProvider)
      .open(
        currentUserId: session.userId,
        otherUserId: profile.id,
        otherUserDisplayName: profile.fullName,
      );
  ref.read(threadsDestinationProvider.notifier).clear();
  ref.read(selectedChannelProvider.notifier).select(channel);
  unawaited(ref.read(channelSidebarProvider.notifier).refresh());
}

final AsyncNotifierProvider<ChannelSidebarController, ChannelSidebarSnapshot>
channelSidebarProvider =
    AsyncNotifierProvider<ChannelSidebarController, ChannelSidebarSnapshot>(
      () => ChannelSidebarController(
        authSessionProvider,
        channelSidebarRepositoryProvider,
      ),
    );

final channelPostsProvider = AsyncNotifierProvider.autoDispose
    .family<ChannelPostsController, ChannelPostsViewState, String>(
      (String channelId) => ChannelPostsController(
        channelId,
        authSessionProvider,
        channelPostRepositoryProvider,
        messageSenderProvider,
        reactionRepositoryProvider,
      ),
    );

final threadProvider = AsyncNotifierProvider.autoDispose
    .family<ThreadController, ThreadViewState, String>(
      (String rootPostId) => ThreadController(
        rootPostId,
        authSessionProvider,
        threadRepositoryProvider,
        messageSenderProvider,
        reactionRepositoryProvider,
      ),
    );

final followedThreadsProvider = AsyncNotifierProvider.autoDispose
    .family<FollowedThreadsController, FollowedThreadsViewState, String>(
      (String teamId) => FollowedThreadsController(
        teamId,
        authSessionProvider,
        followedThreadsRepositoryProvider,
      ),
    );

Future<void> refreshChannelSidebar(WidgetRef ref) =>
    ref.read(channelSidebarProvider.notifier).refresh();
