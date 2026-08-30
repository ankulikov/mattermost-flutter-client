import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/platform/in_app_webview_sso_browser_gateway.dart';
import 'package:mattermost_flutter/src/data/providers/infrastructure_providers.dart';
import 'package:mattermost_flutter/src/data/providers/session_providers.dart';
import 'package:mattermost_flutter/src/data/repositories/api_server_sso_discovery.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_auth_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/attachment_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/auth_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/channel_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/direct_channel_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/emoji_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/followed_threads_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/message_mapper.dart';
import 'package:mattermost_flutter/src/domain/repositories/message_sender.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/reaction_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_avatar_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_mention_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_profile_repository.dart';
import 'package:mattermost_flutter/src/features/attachments/data/api_attachment_repository.dart';
import 'package:mattermost_flutter/src/features/channels/data/api_channel_sidebar_repository.dart';
import 'package:mattermost_flutter/src/features/channels/data/api_direct_channel_repository.dart';
import 'package:mattermost_flutter/src/features/emojis/data/api_custom_emoji_repository.dart';
import 'package:mattermost_flutter/src/features/messages/data/api_message_sender.dart';
import 'package:mattermost_flutter/src/features/messages/data/api_reaction_repository.dart';
import 'package:mattermost_flutter/src/features/messages/data/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/features/posts/data/api_channel_post_repository.dart';
import 'package:mattermost_flutter/src/features/threads/data/api_followed_threads_repository.dart';
import 'package:mattermost_flutter/src/features/threads/data/api_thread_repository.dart';
import 'package:mattermost_flutter/src/features/users/data/api_user_avatar_repository.dart';
import 'package:mattermost_flutter/src/features/users/data/api_user_mention_repository.dart';
import 'package:mattermost_flutter/src/features/users/data/api_user_profile_repository.dart';

final Provider<MattermostAuthRepository> mattermostAuthRepositoryProvider =
    Provider<MattermostAuthRepository>((Ref ref) {
      return MattermostAuthRepository(
        credentialStore: ref.watch(credentialStoreProvider),
        activeAccount: ref.watch(activeAccountContextProvider),
        clientFactory: ref.watch(mattermostApiClientFactoryProvider),
        serverSsoDiscovery: ApiServerSsoDiscovery(),
        ssoBrowserGateway: InAppWebViewSsoBrowserGateway(),
      );
    });

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
      (Ref ref) => ref.watch(mattermostAuthRepositoryProvider),
    );

final Provider<UserAvatarRepository> userAvatarRepositoryProvider =
    Provider<UserAvatarRepository>(
      (Ref ref) => ApiUserAvatarRepository(
        api: ref.watch(activeMattermostApiProvider),
        cache: ref.watch(userAvatarCacheProvider),
      ),
    );

final Provider<AttachmentRepository> attachmentRepositoryProvider =
    Provider<AttachmentRepository>(
      (Ref ref) => ApiAttachmentRepository(
        api: ref.watch(activeMattermostApiProvider),
        fileSaver: ref.watch(attachmentFileSaverProvider),
      ),
    );

final Provider<CustomEmojiRepository> customEmojiRepositoryProvider =
    Provider<CustomEmojiRepository>(
      (Ref ref) => ApiCustomEmojiRepository(
        api: ref.watch(activeMattermostApiProvider),
        cache: ref.watch(customEmojiCacheProvider),
      ),
    );

final Provider<UserProfileRepository> userProfileRepositoryProvider =
    Provider<UserProfileRepository>(
      (Ref ref) =>
          ApiUserProfileRepository(api: ref.watch(activeMattermostApiProvider)),
    );

final Provider<UserMentionRepository> userMentionRepositoryProvider =
    Provider<UserMentionRepository>(
      (Ref ref) =>
          ApiUserMentionRepository(api: ref.watch(activeMattermostApiProvider)),
    );

final Provider<DirectChannelRepository> directChannelRepositoryProvider =
    Provider<DirectChannelRepository>(
      (Ref ref) => ApiDirectChannelRepository(
        api: ref.watch(activeMattermostApiProvider),
      ),
    );

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
