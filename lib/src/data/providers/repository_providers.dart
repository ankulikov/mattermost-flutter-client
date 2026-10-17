import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/database/database_provider.dart';
import 'package:mattermost_flutter/src/data/mappers/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/data/platform/in_app_webview_sso_browser_gateway.dart';
import 'package:mattermost_flutter/src/data/providers/infrastructure_providers.dart';
import 'package:mattermost_flutter/src/data/providers/session_providers.dart';
import 'package:mattermost_flutter/src/data/repositories/api_attachment_repository.dart';
import 'package:mattermost_flutter/src/data/repositories/api_custom_emoji_repository.dart';
import 'package:mattermost_flutter/src/data/repositories/api_server_sso_discovery.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_auth_repository.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_channel_repository.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_post_action_repository.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_post_repository.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_rich_attachment_option_repository.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_thread_repository.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_user_repository.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/attachment_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/auth_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/channel_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/emoji_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/message_mapper.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_action_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/rich_attachment_option_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_repository.dart';
import 'package:mattermost_flutter/src/domain/services/realtime_connection_service.dart';
import 'package:mattermost_flutter/src/features/channel_members/data/mattermost_channel_members_repository.dart';
import 'package:mattermost_flutter/src/features/channel_members/domain/channel_members_repository.dart';
import 'package:mattermost_flutter/src/features/file_upload/data/mattermost_file_upload_repository.dart';
import 'package:mattermost_flutter/src/features/file_upload/data/system_upload_file_picker.dart';
import 'package:mattermost_flutter/src/features/file_upload/domain/file_upload.dart';
import 'package:mattermost_flutter/src/features/inbox/data/repositories/mattermost_inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/data/repositories/mattermost_postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/data/repositories/mattermost_viewed_channel_posts_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/viewed_channel_posts_repository.dart';
import 'package:mattermost_flutter/src/features/mentions/data/repositories/mattermost_mention_repository.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/repositories/mention_repository.dart';
import 'package:mattermost_flutter/src/features/preferences/data/repositories/drift_user_preferences_repository.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/repositories/user_preferences_repository.dart';
import 'package:mattermost_flutter/src/features/profile/data/repositories/mattermost_current_user_profile_repository.dart';
import 'package:mattermost_flutter/src/features/profile/domain/repositories/current_user_profile_repository.dart';
import 'package:mattermost_flutter/src/features/search/data/repositories/mattermost_message_search_repository.dart';
import 'package:mattermost_flutter/src/features/search/data/repositories/mattermost_message_search_timezone_repository.dart';
import 'package:mattermost_flutter/src/features/search/domain/repositories/message_search_repository.dart';
import 'package:mattermost_flutter/src/features/search/domain/repositories/message_search_timezone_repository.dart';
import 'package:mattermost_flutter/src/features/updates/data/github_app_update_repository.dart';
import 'package:mattermost_flutter/src/features/updates/domain/repositories/app_update_repository.dart';

final Provider<RealtimeConnectionService> realtimeConnectionServiceProvider =
    Provider<RealtimeConnectionService>(
      (Ref ref) => ref.watch(sessionRealtimeServiceProvider),
    );

final Provider<AppUpdateRepository> appUpdateRepositoryProvider =
    Provider<AppUpdateRepository>(
      (Ref ref) => GithubAppUpdateRepository(
        releaseApi: ref.watch(githubReleaseApiProvider),
        installedApplicationSource: ref.watch(
          installedApplicationSourceProvider,
        ),
        installerGateway: ref.watch(packageInstallerGatewayProvider),
        downloader: ref.watch(updateArtifactDownloaderProvider),
      ),
    );

final Provider<UploadFilePicker> uploadFilePickerProvider =
    Provider<UploadFilePicker>((Ref ref) => const SystemUploadFilePicker());

final Provider<FileUploadRepository> fileUploadRepositoryProvider =
    Provider<FileUploadRepository>(
      (Ref ref) => MattermostFileUploadRepository(
        ref.watch(activeMattermostApiProvider),
      ),
    );

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

final Provider<UserPreferencesRepository> userPreferencesRepositoryProvider =
    Provider<UserPreferencesRepository>((Ref ref) {
      final session = ref.watch(activeAccountSessionProvider);
      if (session == null) {
        throw StateError('No active Mattermost account for preferences');
      }
      return DriftUserPreferencesRepository(
        database: ref.watch(appDatabaseProvider),
        accountScopeId: session.durableDataScopeId,
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
        realtime: ref.watch(sessionRealtimeServiceProvider),
      ),
    );

final Provider<ChannelMembersRepository> channelMembersRepositoryProvider =
    Provider<ChannelMembersRepository>((Ref ref) {
      final MattermostApi api = ref.watch(activeMattermostApiProvider);
      if (api is! MattermostChannelMembersApi) {
        throw StateError(
          'The active Mattermost API does not support channel members',
        );
      }
      return MattermostChannelMembersRepository(
        api: api as MattermostChannelMembersApi,
        users: ref.watch(userRepositoryProvider),
      );
    });

final Provider<PostRepository> postRepositoryProvider =
    Provider<PostRepository>(
      (Ref ref) => MattermostPostRepository(
        api: ref.watch(activeMattermostApiProvider),
        messageMapper: ref.watch(mattermostMessageMapperProvider),
        users: ref.watch(userRepositoryProvider),
        realtime: ref.watch(sessionRealtimeServiceProvider),
      ),
    );

final Provider<PostActionRepository> postActionRepositoryProvider =
    Provider<PostActionRepository>(
      (Ref ref) => MattermostPostActionRepository(
        api: ref.watch(activeMattermostApiProvider),
        messageMapper: ref.watch(mattermostMessageMapperProvider),
        users: ref.watch(userRepositoryProvider),
        realtime: ref.watch(sessionRealtimeServiceProvider),
      ),
    );

final Provider<RichAttachmentOptionRepository>
richAttachmentOptionRepositoryProvider =
    Provider<RichAttachmentOptionRepository>(
      (Ref ref) => MattermostRichAttachmentOptionRepository(
        api: ref.watch(activeMattermostApiProvider),
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

final Provider<MessageSearchRepository> messageSearchRepositoryProvider =
    Provider<MessageSearchRepository>(
      (Ref ref) => MattermostMessageSearchRepository(
        api: ref.watch(activeMattermostApiProvider),
        messageMapper: ref.watch(mattermostMessageMapperProvider),
        users: ref.watch(userRepositoryProvider),
      ),
    );

final Provider<MessageSearchTimezoneRepository>
messageSearchTimezoneRepositoryProvider =
    Provider<MessageSearchTimezoneRepository>(
      (Ref ref) => MattermostMessageSearchTimezoneRepository(
        api: ref.watch(activeMattermostApiProvider),
      ),
    );

final Provider<PostponedRepository> postponedRepositoryProvider =
    Provider<PostponedRepository>(
      (Ref ref) => MattermostPostponedRepository(
        api: ref.watch(activeMattermostApiProvider),
      ),
    );

final Provider<ViewedChannelPostsRepository>
viewedChannelPostsRepositoryProvider = Provider<ViewedChannelPostsRepository>(
  (Ref ref) => MattermostViewedChannelPostsRepository(
    api: ref.watch(activeMattermostApiProvider),
  ),
);

final Provider<InboxRepository> inboxRepositoryProvider =
    Provider<InboxRepository>(
      (Ref ref) => MattermostInboxRepository(
        api: ref.watch(activeMattermostApiProvider),
        messageMapper: ref.watch(mattermostMessageMapperProvider),
        postponed: ref.watch(postponedRepositoryProvider),
        viewedChannelPosts: ref.watch(viewedChannelPostsRepositoryProvider),
        userGroupCache: ref.watch(userGroupMembershipCacheProvider),
        counterCache: ref.watch(inboxCounterCacheProvider),
        realtime: ref.watch(sessionRealtimeServiceProvider),
      ),
    );
