import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/data/cache/avatar_cache.dart';
import 'package:mattermost_flutter/src/data/cache/custom_emoji_cache.dart';
import 'package:mattermost_flutter/src/data/database/database_provider.dart';
import 'package:mattermost_flutter/src/data/database/user_profile_cache_dao.dart';
import 'package:mattermost_flutter/src/data/platform/in_app_webview_sso_browser_gateway.dart';
import 'package:mattermost_flutter/src/data/platform/system_attachment_file_saver.dart';
import 'package:mattermost_flutter/src/data/storage/credential_store.dart';
import 'package:mattermost_flutter/src/data/storage/secure_credential_store.dart';
import 'package:mattermost_flutter/src/domain/repositories/attachment_repository.dart';
import 'package:mattermost_flutter/src/features/auth/domain/sso_browser_gateway.dart';

/// Process-wide infrastructure adapters. These providers do not expose UI
/// state and are composed into repositories by [repository_providers.dart].
final Provider<CredentialStore> credentialStoreProvider =
    Provider<CredentialStore>((Ref ref) => SecureCredentialStore());

final Provider<MattermostApiClientFactory> mattermostApiClientFactoryProvider =
    Provider<MattermostApiClientFactory>(
      (Ref ref) => const MattermostClientFactory(),
    );

final Provider<UserProfileCache> userProfileCacheProvider =
    Provider<UserProfileCache>(
      (Ref ref) => DriftUserProfileCache(ref.watch(appDatabaseProvider)),
    );

final Provider<UserAvatarCache> userAvatarCacheProvider =
    Provider<UserAvatarCache>((Ref ref) => FlutterUserAvatarCache());

final Provider<CustomEmojiCache> customEmojiCacheProvider =
    Provider<CustomEmojiCache>((Ref ref) => FlutterCustomEmojiCache());

final Provider<AttachmentFileSaver> attachmentFileSaverProvider =
    Provider<AttachmentFileSaver>(
      (Ref ref) => const SystemAttachmentFileSaver(),
    );

final Provider<SsoBrowserGateway> ssoBrowserGatewayProvider =
    Provider<SsoBrowserGateway>((Ref ref) => InAppWebViewSsoBrowserGateway());
