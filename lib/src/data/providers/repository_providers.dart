import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/data/platform/in_app_webview_sso_browser_gateway.dart';
import 'package:mattermost_flutter/src/data/providers/infrastructure_providers.dart';
import 'package:mattermost_flutter/src/data/providers/session_providers.dart';
import 'package:mattermost_flutter/src/data/repositories/api_attachment_repository.dart';
import 'package:mattermost_flutter/src/data/repositories/api_custom_emoji_repository.dart';
import 'package:mattermost_flutter/src/data/repositories/api_server_sso_discovery.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_auth_repository.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_channel_repository.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_post_repository.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_thread_repository.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_user_repository.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/attachment_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/auth_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/channel_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/emoji_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/message_mapper.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/data/repositories/mattermost_inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/data/repositories/mattermost_postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/features/mentions/data/repositories/mattermost_mention_repository.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/repositories/mention_repository.dart';
import 'package:mattermost_flutter/src/features/profile/data/repositories/mattermost_current_user_profile_repository.dart';
import 'package:mattermost_flutter/src/features/profile/domain/repositories/current_user_profile_repository.dart';

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

final Provider<UserRepository> userRepositoryProvider =
    Provider<UserRepository>((Ref ref) {
      final session = ref.watch(activeAccountSessionProvider);
      if (session == null) {
        throw StateError('No active Mattermost account for user repository');
      }
      return MattermostUserRepository(
        api: ref.watch(activeMattermostApiProvider),
        cache: ref.watch(userProfileCacheProvider),
        avatarCache: ref.watch(userAvatarCacheProvider),
        accountScopeId: session.durableDataScopeId,
      );
    });

final Provider<CurrentUserProfileRepository>
currentUserProfileRepositoryProvider = Provider<CurrentUserProfileRepository>((
  Ref ref,
) {
  final session = ref.watch(activeAccountSessionProvider);
  if (session == null) {
    throw StateError('No active Mattermost account for profile repository');
  }
  final MattermostApi api = ref.watch(activeMattermostApiProvider);
  if (api is! MattermostProfileApi) {
    throw StateError('The active Mattermost API does not support profiles');
  }
  return MattermostCurrentUserProfileRepository(
    api: api,
    userId: session.userId,
  );
});

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
        recentCache: ref.watch(recentEmojiCacheProvider),
      ),
    );

final Provider<MentionRepository> mentionRepositoryProvider =
    Provider<MentionRepository>(
      (Ref ref) => MattermostMentionRepository(
        api: ref.watch(activeMattermostApiProvider),
      ),
    );

final Provider<MessageMapper<MattermostPostDto, UserSummary>>
mattermostMessageMapperProvider =
    Provider<MessageMapper<MattermostPostDto, UserSummary>>(
      (Ref ref) => const MattermostMessageMapper(),
    );

final Provider<ChannelRepository> channelRepositoryProvider =
    Provider<ChannelRepository>(
      (Ref ref) => MattermostChannelRepository(
        api: ref.watch(activeMattermostApiProvider),
        users: ref.watch(userRepositoryProvider),
      ),
    );

final Provider<PostRepository> postRepositoryProvider =
    Provider<PostRepository>(
      (Ref ref) => MattermostPostRepository(
        api: ref.watch(activeMattermostApiProvider),
        messageMapper: ref.watch(mattermostMessageMapperProvider),
        users: ref.watch(userRepositoryProvider),
      ),
    );

final Provider<ThreadRepository> threadRepositoryProvider =
    Provider<ThreadRepository>(
      (Ref ref) => MattermostThreadRepository(
        api: ref.watch(activeMattermostApiProvider),
        messageMapper: ref.watch(mattermostMessageMapperProvider),
        users: ref.watch(userRepositoryProvider),
      ),
    );

final Provider<PostponedRepository> postponedRepositoryProvider =
    Provider<PostponedRepository>(
      (Ref ref) => MattermostPostponedRepository(
        api: ref.watch(activeMattermostApiProvider),
      ),
    );

final Provider<InboxRepository> inboxRepositoryProvider =
    Provider<InboxRepository>(
      (Ref ref) => MattermostInboxRepository(
        api: ref.watch(activeMattermostApiProvider),
        messageMapper: ref.watch(mattermostMessageMapperProvider),
        postponed: ref.watch(postponedRepositoryProvider),
        webSocketGateway: ref.watch(webSocketGatewayProvider),
        credentialStore: ref.watch(credentialStoreProvider),
      ),
    );
