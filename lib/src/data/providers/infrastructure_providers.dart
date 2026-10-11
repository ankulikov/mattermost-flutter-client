import 'dart:async';

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

/// Process-wide infrastructure adapters. These providers do not expose UI
/// state and are composed into repositories by [repository_providers.dart].
final Provider<CredentialStore> credentialStoreProvider =
    Provider<CredentialStore>((Ref ref) => SecureCredentialStore());

final Provider<MattermostApiClientFactory> mattermostApiClientFactoryProvider =
    Provider<MattermostApiClientFactory>(
      (Ref ref) => const MattermostClientFactory(),
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
