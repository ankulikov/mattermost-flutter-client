import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/data/providers/repository_providers.dart';
import 'package:mattermost_flutter/src/domain/models/attachment.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/models/post_navigation.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/models/user_avatar.dart';
import 'package:mattermost_flutter/src/domain/models/user_mention.dart';
import 'package:mattermost_flutter/src/domain/services/realtime_connection_service.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_controller.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/group_mention.dart';
import 'package:mattermost_flutter/src/features/profile/presentation/current_user_profile_controller.dart';
import 'package:mattermost_flutter/src/features/updates/presentation/app_update_controller.dart';
import 'package:mattermost_flutter/src/ui/auth/auth_controller.dart';
import 'package:mattermost_flutter/src/ui/channels/channel_sidebar_controller.dart';
import 'package:mattermost_flutter/src/ui/posts/channel_posts_controller.dart';
import 'package:mattermost_flutter/src/ui/posts/post_permalink_controller.dart';
import 'package:mattermost_flutter/src/ui/threads/followed_threads_controller.dart';
import 'package:mattermost_flutter/src/ui/threads/thread_controller.dart';

export '../data/providers/repository_providers.dart';

final NotifierProvider<AuthController, AuthState> authControllerProvider =
    NotifierProvider<AuthController, AuthState>(
      () => AuthController(authRepositoryProvider),
    );

final NotifierProvider<AppUpdateController, AppUpdateViewState>
appUpdateControllerProvider =
    NotifierProvider<AppUpdateController, AppUpdateViewState>(
      () => AppUpdateController(
        appUpdateRepositoryProvider,
        userPreferencesRepositoryProvider,
      ),
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

/// Keeps the session-owned realtime service alive independently of open tabs.
final StreamProvider<RealtimeConnectionStatus>
realtimeConnectionStatusProvider = StreamProvider<RealtimeConnectionStatus>(
  (Ref ref) => ref.watch(realtimeConnectionServiceProvider).connectionStatuses,
);

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

final groupMentionsProvider = FutureProvider.autoDispose
    .family<List<GroupMention>, String>((Ref ref, String lookupKey) {
      final List<String> names = lookupKey.isEmpty
          ? const <String>[]
          : lookupKey.split(',');
      if (names.isEmpty) return const <GroupMention>[];
      final RequestCancellation cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      return cancellation.run(
        () => ref.watch(mentionRepositoryProvider).resolveGroupsByNames(names),
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

final reactionUsersProvider = FutureProvider.autoDispose
    .family<List<UserSummary>, String>((Ref ref, String lookupKey) {
      final List<String> userIds = lookupKey.isEmpty
          ? const <String>[]
          : lookupKey.split('\u0000');
      if (userIds.isEmpty) return const <UserSummary>[];
      final RequestCancellation cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      return cancellation.run(
        () => ref.watch(userRepositoryProvider).getUsers(userIds),
      );
    });

final AsyncNotifierProvider<
  CurrentUserProfileController,
  CurrentUserProfileViewState
>
currentUserProfileProvider =
    AsyncNotifierProvider<
      CurrentUserProfileController,
      CurrentUserProfileViewState
    >(
      () => CurrentUserProfileController(
        authSessionProvider,
        currentUserProfileRepositoryProvider,
      ),
    );

final AsyncNotifierProvider<ChannelSidebarController, ChannelSidebarViewState>
channelSidebarProvider =
    AsyncNotifierProvider<ChannelSidebarController, ChannelSidebarViewState>(
      () => ChannelSidebarController(
        authSessionProvider,
        channelRepositoryProvider,
      ),
    );

final channelPostsProvider = AsyncNotifierProvider.autoDispose
    .family<ChannelPostsController, ChannelPostsViewState, String>(
      (String channelId) => ChannelPostsController(
        channelId,
        authSessionProvider,
        postRepositoryProvider,
      ),
    );

/// A route-local post timeline. It prevents a linked historical window from
/// replacing the snapshot owned by the route beneath it.
typedef ScopedChannelPostsRequest = ({String channelId, String scopeId});

final scopedChannelPostsProvider = AsyncNotifierProvider.autoDispose
    .family<
      ChannelPostsController,
      ChannelPostsViewState,
      ScopedChannelPostsRequest
    >(
      (ScopedChannelPostsRequest request) => ChannelPostsController(
        request.channelId,
        authSessionProvider,
        postRepositoryProvider,
      ),
    );

/// Route-scoped resolver for one `/post/:postId` navigation entry.
final postPermalinkProvider = AsyncNotifierProvider.autoDispose
    .family<PostPermalinkController, PostNavigationTarget, String>(
      (String postId) => PostPermalinkController(
        postId,
        authSessionProvider,
        postRepositoryProvider,
      ),
    );

typedef ThreadRequest = ({
  String rootPostId,
  String teamId,
  bool allowsFollowing,
});

/// A route-local thread snapshot for permalink targets.
typedef ScopedThreadRequest = ({ThreadRequest request, String scopeId});

final threadProvider = AsyncNotifierProvider.autoDispose
    .family<ThreadController, ThreadViewState, ThreadRequest>(
      (ThreadRequest request) => ThreadController(
        request.rootPostId,
        authSessionProvider,
        threadRepositoryProvider,
        postRepositoryProvider,
        postponedRepositoryProvider,
        request.teamId,
        request.allowsFollowing,
      ),
    );

final scopedThreadProvider = AsyncNotifierProvider.autoDispose
    .family<ThreadController, ThreadViewState, ScopedThreadRequest>(
      (ScopedThreadRequest scoped) => ThreadController(
        scoped.request.rootPostId,
        authSessionProvider,
        threadRepositoryProvider,
        postRepositoryProvider,
        postponedRepositoryProvider,
        scoped.request.teamId,
        scoped.request.allowsFollowing,
      ),
    );

final followedThreadsProvider = AsyncNotifierProvider.autoDispose
    .family<FollowedThreadsController, FollowedThreadsViewState, String>(
      (String teamId) => FollowedThreadsController(
        teamId,
        authSessionProvider,
        threadRepositoryProvider,
      ),
    );

final AsyncNotifierProvider<InboxController, InboxViewState> inboxProvider =
    AsyncNotifierProvider<InboxController, InboxViewState>(
      () => InboxController(
        authSessionProvider,
        inboxRepositoryProvider,
        postponedRepositoryProvider,
      ),
    );

Future<void> refreshChannelSidebar(WidgetRef ref) =>
    ref.read(channelSidebarProvider.notifier).refresh();
