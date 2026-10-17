import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/data/cache/avatar_cache.dart';
import 'package:mattermost_flutter/src/data/cache/custom_emoji_cache.dart';
import 'package:mattermost_flutter/src/data/database/database_provider.dart';
import 'package:mattermost_flutter/src/data/database/inbox_counter_cache.dart';
import 'package:mattermost_flutter/src/data/database/recent_emoji_cache.dart';
import 'package:mattermost_flutter/src/data/database/user_group_membership_cache.dart';
import 'package:mattermost_flutter/src/data/database/user_profile_cache_dao.dart';
import 'package:mattermost_flutter/src/data/platform/system_attachment_file_saver.dart';
import 'package:mattermost_flutter/src/data/providers/session_providers.dart';
import 'package:mattermost_flutter/src/data/realtime/mattermost_websocket_gateway.dart';
import 'package:mattermost_flutter/src/data/realtime/network_availability_monitor.dart';
import 'package:mattermost_flutter/src/data/realtime/session_realtime_service.dart';
import 'package:mattermost_flutter/src/data/realtime/websocket_gateway.dart';
import 'package:mattermost_flutter/src/data/storage/credential_store.dart';
import 'package:mattermost_flutter/src/data/storage/secure_credential_store.dart';
import 'package:mattermost_flutter/src/domain/repositories/attachment_repository.dart';
import 'package:mattermost_flutter/src/features/updates/data/android_package_installer_gateway.dart';
import 'package:mattermost_flutter/src/features/updates/data/github_release_api.dart';
import 'package:mattermost_flutter/src/features/updates/data/installed_application_source.dart';
import 'package:mattermost_flutter/src/features/updates/data/update_artifact_downloader.dart';
import 'package:mattermost_flutter/src/features/updates/data/update_artifact_downloader_factory.dart';

/// Process-wide infrastructure adapters. These providers do not expose UI
/// state and are composed into repositories by [repository_providers.dart].
final Provider<CredentialStore> credentialStoreProvider =
    Provider<CredentialStore>((Ref ref) => SecureCredentialStore());

final Provider<MattermostApiClientFactory> mattermostApiClientFactoryProvider =
    Provider<MattermostApiClientFactory>(
      (Ref ref) => const MattermostClientFactory(),
    );

final Provider<Dio> githubUpdateDioProvider = Provider<Dio>((Ref ref) {
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.github.com',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: const <String, String>{
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'mattermost-flutter-client-updater',
      },
    ),
  );
  ref.onDispose(() => dio.close(force: true));
  return dio;
});

final Provider<GithubReleaseApi> githubReleaseApiProvider =
    Provider<GithubReleaseApi>(
      (Ref ref) => GithubReleaseApi(dio: ref.watch(githubUpdateDioProvider)),
    );

final Provider<InstalledApplicationSource> installedApplicationSourceProvider =
    Provider<InstalledApplicationSource>(
      (Ref ref) => const PackageInfoInstalledApplicationSource(),
    );

final Provider<PackageInstallerGateway> packageInstallerGatewayProvider =
    Provider<PackageInstallerGateway>(
      (Ref ref) => AndroidPackageInstallerGateway(),
    );

final Provider<UpdateArtifactDownloader> updateArtifactDownloaderProvider =
    Provider<UpdateArtifactDownloader>(
      (Ref ref) =>
          createUpdateArtifactDownloader(ref.watch(githubUpdateDioProvider)),
    );

final Provider<WebSocketGateway> webSocketGatewayProvider =
    Provider<WebSocketGateway>(
      (Ref ref) => MattermostWebSocketGateway(
        networkMonitor: ConnectivityNetworkAvailabilityMonitor(),
      ),
    );

final Provider<SessionRealtimeService> sessionRealtimeServiceProvider =
    Provider<SessionRealtimeService>((Ref ref) {
      final SessionRealtimeService service = SessionRealtimeService(
        gateway: ref.watch(webSocketGatewayProvider),
        credentialStore: ref.watch(credentialStoreProvider),
      );
      ref.listen(
        activeAccountSessionProvider,
        (previous, next) => unawaited(service.setSession(next)),
        fireImmediately: true,
      );
      ref.onDispose(() => unawaited(service.dispose()));
      return service;
    });

final Provider<UserProfileCache> userProfileCacheProvider =
    Provider<UserProfileCache>(
      (Ref ref) => DriftUserProfileCache(ref.watch(appDatabaseProvider)),
    );

final Provider<UserAvatarCache> userAvatarCacheProvider =
    Provider<UserAvatarCache>((Ref ref) => FlutterUserAvatarCache());

final Provider<CustomEmojiCache> customEmojiCacheProvider =
    Provider<CustomEmojiCache>((Ref ref) => FlutterCustomEmojiCache());

final Provider<RecentEmojiCache> recentEmojiCacheProvider =
    Provider<RecentEmojiCache>(
      (Ref ref) => DriftRecentEmojiCache(ref.watch(appDatabaseProvider)),
    );

final Provider<UserGroupMembershipCache> userGroupMembershipCacheProvider =
    Provider<UserGroupMembershipCache>(
      (Ref ref) =>
          DriftUserGroupMembershipCache(ref.watch(appDatabaseProvider)),
    );

final Provider<InboxCounterCache> inboxCounterCacheProvider =
    Provider<InboxCounterCache>(
      (Ref ref) => DriftInboxCounterCache(ref.watch(appDatabaseProvider)),
    );

final Provider<AttachmentFileSaver> attachmentFileSaverProvider =
    Provider<AttachmentFileSaver>(
      (Ref ref) => const SystemAttachmentFileSaver(),
    );
