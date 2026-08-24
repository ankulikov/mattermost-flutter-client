import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/database/database_provider.dart';
import 'package:mattermost_flutter/src/features/auth/data/secure_credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/auth_controller.dart';
import 'package:mattermost_flutter/src/features/channels/data/api_channel_sidebar_repository.dart';
import 'package:mattermost_flutter/src/features/channels/data/channel_sidebar_store.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar_repository.dart';

final Provider<ChannelSidebarStore> channelSidebarStoreProvider =
    Provider<ChannelSidebarStore>((Ref ref) {
      final ChannelSidebarStore store = ChannelSidebarStore(
        ref.watch(appDatabaseProvider),
      );
      ref.onDispose(() => unawaited(store.close()));
      return store;
    });

final Provider<ChannelSidebarRepository> channelSidebarRepositoryProvider =
    Provider<ChannelSidebarRepository>(
      (Ref ref) => ApiChannelSidebarRepository(
        credentialStore: SecureCredentialStore(),
        store: ref.watch(channelSidebarStoreProvider),
      ),
    );

final StreamProvider<ChannelSidebarSnapshot> channelSidebarProvider =
    StreamProvider<ChannelSidebarSnapshot>((Ref ref) {
      final AuthSession? session = ref.watch(
        authControllerProvider.select((AuthState state) => state.session),
      );
      if (session == null) {
        return Stream<ChannelSidebarSnapshot>.value(
          const ChannelSidebarSnapshot(),
        );
      }
      final ChannelSidebarRepository repository = ref.watch(
        channelSidebarRepositoryProvider,
      );
      unawaited(repository.refresh(session));
      return repository.watch(session.accountId);
    });

Future<void> refreshChannelSidebar(WidgetRef ref) async {
  final AuthSession? session = ref.read(authControllerProvider).session;
  if (session == null) return;
  await ref.read(channelSidebarRepositoryProvider).refresh(session);
}
