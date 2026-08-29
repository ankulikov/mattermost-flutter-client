import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/api/active_mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/core/database/database_provider.dart';
import 'package:mattermost_flutter/src/features/attachments/data/api_attachment_repository.dart';
import 'package:mattermost_flutter/src/features/attachments/data/system_attachment_file_saver.dart';
import 'package:mattermost_flutter/src/features/attachments/domain/attachment_repository.dart';
import 'package:mattermost_flutter/src/features/auth/data/credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/data/pat_auth_repository.dart';
import 'package:mattermost_flutter/src/features/auth/data/secure_credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_repository.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/auth_controller.dart';
import 'package:mattermost_flutter/src/features/channels/data/api_channel_sidebar_repository.dart';
import 'package:mattermost_flutter/src/features/channels/data/api_direct_channel_repository.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar_repository.dart';
import 'package:mattermost_flutter/src/features/channels/domain/direct_channel_repository.dart';
import 'package:mattermost_flutter/src/features/channels/presentation/channel_sidebar_controller.dart';
import 'package:mattermost_flutter/src/features/channels/presentation/selected_channel_controller.dart';
import 'package:mattermost_flutter/src/features/emojis/data/api_custom_emoji_repository.dart';
import 'package:mattermost_flutter/src/features/emojis/data/custom_emoji_cache.dart';
import 'package:mattermost_flutter/src/features/emojis/domain/custom_emoji.dart';
import 'package:mattermost_flutter/src/features/emojis/domain/custom_emoji_repository.dart';
import 'package:mattermost_flutter/src/features/messages/data/api_message_sender.dart';
import 'package:mattermost_flutter/src/features/messages/data/api_reaction_repository.dart';
import 'package:mattermost_flutter/src/features/messages/data/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message_mapper.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message_sender.dart';
import 'package:mattermost_flutter/src/features/messages/domain/reaction_repository.dart';
import 'package:mattermost_flutter/src/features/posts/data/api_channel_post_repository.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post_repository.dart';
import 'package:mattermost_flutter/src/features/posts/presentation/channel_posts_controller.dart';
import 'package:mattermost_flutter/src/features/threads/data/api_followed_threads_repository.dart';
import 'package:mattermost_flutter/src/features/threads/data/api_thread_repository.dart';
import 'package:mattermost_flutter/src/features/threads/domain/followed_threads_repository.dart';
import 'package:mattermost_flutter/src/features/threads/domain/thread_repository.dart';
import 'package:mattermost_flutter/src/features/threads/presentation/followed_threads_controller.dart';
import 'package:mattermost_flutter/src/features/threads/presentation/thread_controller.dart';
import 'package:mattermost_flutter/src/features/users/data/api_user_avatar_repository.dart';
import 'package:mattermost_flutter/src/features/users/data/api_user_profile_repository.dart';
import 'package:mattermost_flutter/src/features/users/data/cached_user_profile_api.dart';
import 'package:mattermost_flutter/src/features/users/data/user_avatar_cache.dart';
import 'package:mattermost_flutter/src/features/users/data/user_profile_cache.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_avatar.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_avatar_repository.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_profile.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_profile_repository.dart';

final Provider<CredentialStore> credentialStoreProvider =
    Provider<CredentialStore>((Ref ref) => SecureCredentialStore());

final Provider<MattermostApiClientFactory> mattermostApiClientFactoryProvider =
    Provider<MattermostApiClientFactory>(
      (Ref ref) => const MattermostClientFactory(),
    );

final Provider<PatAuthRepository> patAuthRepositoryProvider =
    Provider<PatAuthRepository>((Ref ref) {
      final PatAuthRepository repository = PatAuthRepository(
        credentialStore: ref.watch(credentialStoreProvider),
        clientFactory: ref.watch(mattermostApiClientFactoryProvider),
      );
      ref.onDispose(repository.dispose);
      return repository;
    });

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>((Ref ref) => ref.watch(patAuthRepositoryProvider));

final Provider<ActiveMattermostApi> activeMattermostApiSourceProvider =
    Provider<ActiveMattermostApi>(
      (Ref ref) => ref.watch(patAuthRepositoryProvider),
    );

final NotifierProvider<AuthController, AuthState> authControllerProvider =
    NotifierProvider<AuthController, AuthState>(
      () => AuthController(authRepositoryProvider),
    );

final Provider<AuthSession?> authSessionProvider = Provider<AuthSession?>((
  Ref ref,
) {
  return ref.watch(
    authControllerProvider.select((AuthState state) => state.session),
  );
});

final Provider<UserProfileCache> userProfileCacheProvider =
    Provider<UserProfileCache>(
      (Ref ref) => DriftUserProfileCache(ref.watch(appDatabaseProvider)),
    );

final Provider<MattermostApi> activeMattermostApiProvider =
    Provider<MattermostApi>((Ref ref) {
      final AuthSession? session = ref.watch(authSessionProvider);
      final MattermostApi? api = ref
          .watch(activeMattermostApiSourceProvider)
          .api;
      if (session == null || api == null) {
        throw StateError('No API client for the active Mattermost account');
      }
      return CachedUserProfileApi(
        delegate: api,
        cache: ref.watch(userProfileCacheProvider),
        accountId: session.durableDataScopeId,
      );
    });

final Provider<UserAvatarCache> userAvatarCacheProvider =
    Provider<UserAvatarCache>((Ref ref) => FlutterUserAvatarCache());

final Provider<UserAvatarRepository> userAvatarRepositoryProvider =
    Provider<UserAvatarRepository>(
      (Ref ref) => ApiUserAvatarRepository(
        api: ref.watch(activeMattermostApiProvider),
        cache: ref.watch(userAvatarCacheProvider),
      ),
    );

final Provider<AttachmentFileSaver> attachmentFileSaverProvider =
    Provider<AttachmentFileSaver>(
      (Ref ref) => const SystemAttachmentFileSaver(),
    );

final Provider<AttachmentRepository> attachmentRepositoryProvider =
    Provider<AttachmentRepository>(
      (Ref ref) => ApiAttachmentRepository(
        api: ref.watch(activeMattermostApiProvider),
        fileSaver: ref.watch(attachmentFileSaverProvider),
      ),
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
          .watch(userAvatarRepositoryProvider)
          .getAvatar(
            accountId: session.accountId,
            userId: input.userId,
            profileImageUpdatedAt: input.profileImageUpdatedAt,
          );
    });

final Provider<CustomEmojiCache> customEmojiCacheProvider =
    Provider<CustomEmojiCache>((Ref ref) => FlutterCustomEmojiCache());

final Provider<CustomEmojiRepository> customEmojiRepositoryProvider =
    Provider<CustomEmojiRepository>(
      (Ref ref) => ApiCustomEmojiRepository(
        api: ref.watch(activeMattermostApiProvider),
        cache: ref.watch(customEmojiCacheProvider),
      ),
    );

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

final Provider<UserProfileRepository> userProfileRepositoryProvider =
    Provider<UserProfileRepository>(
      (Ref ref) =>
          ApiUserProfileRepository(api: ref.watch(activeMattermostApiProvider)),
    );

final userProfileProvider = FutureProvider.autoDispose
    .family<UserProfile, String>((Ref ref, String userId) {
      final RequestCancellation cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      return cancellation.run(
        () => ref.watch(userProfileRepositoryProvider).getById(userId),
      );
    });

final Provider<DirectChannelRepository> directChannelRepositoryProvider =
    Provider<DirectChannelRepository>(
      (Ref ref) => ApiDirectChannelRepository(
        api: ref.watch(activeMattermostApiProvider),
      ),
    );

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

final Provider<MessageMapper<MattermostPostDto, MattermostUserDto>>
mattermostMessageMapperProvider =
    Provider<MessageMapper<MattermostPostDto, MattermostUserDto>>(
      (Ref ref) => const MattermostMessageMapper(),
    );

final Provider<MessageSender> messageSenderProvider = Provider<MessageSender>(
  (Ref ref) => ApiMessageSender(
    api: ref.watch(activeMattermostApiProvider),
    messageMapper: ref.watch(mattermostMessageMapperProvider),
  ),
);

final Provider<ReactionRepository> reactionRepositoryProvider =
    Provider<ReactionRepository>(
      (Ref ref) =>
          ApiReactionRepository(api: ref.watch(activeMattermostApiProvider)),
    );

final Provider<ChannelSidebarRepository> channelSidebarRepositoryProvider =
    Provider<ChannelSidebarRepository>(
      (Ref ref) => ApiChannelSidebarRepository(
        api: ref.watch(activeMattermostApiProvider),
      ),
    );

final Provider<ChannelPostRepository> channelPostRepositoryProvider =
    Provider<ChannelPostRepository>(
      (Ref ref) => ApiChannelPostRepository(
        api: ref.watch(activeMattermostApiProvider),
        messageMapper: ref.watch(mattermostMessageMapperProvider),
      ),
    );

final Provider<ThreadRepository> threadRepositoryProvider =
    Provider<ThreadRepository>(
      (Ref ref) => ApiThreadRepository(
        api: ref.watch(activeMattermostApiProvider),
        messageMapper: ref.watch(mattermostMessageMapperProvider),
      ),
    );

final Provider<FollowedThreadsRepository> followedThreadsRepositoryProvider =
    Provider<FollowedThreadsRepository>(
      (Ref ref) => ApiFollowedThreadsRepository(
        api: ref.watch(activeMattermostApiProvider),
        messageMapper: ref.watch(mattermostMessageMapperProvider),
      ),
    );

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
