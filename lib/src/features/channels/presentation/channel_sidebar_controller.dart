import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/features/auth/data/secure_credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/auth_controller.dart';
import 'package:mattermost_flutter/src/features/channels/data/api_channel_sidebar_repository.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar_repository.dart';

final Provider<ChannelSidebarRepository> channelSidebarRepositoryProvider =
    Provider<ChannelSidebarRepository>(
      (Ref ref) =>
          ApiChannelSidebarRepository(credentialStore: SecureCredentialStore()),
    );

final AsyncNotifierProvider<ChannelSidebarController, ChannelSidebarSnapshot>
channelSidebarProvider =
    AsyncNotifierProvider<ChannelSidebarController, ChannelSidebarSnapshot>(
      ChannelSidebarController.new,
    );

final class ChannelSidebarController
    extends AsyncNotifier<ChannelSidebarSnapshot> {
  AuthSession? _session;
  ChannelSidebarRepository? _repository;
  bool _refreshing = false;

  @override
  Future<ChannelSidebarSnapshot> build() async {
    final AuthSession? session = ref.watch(
      authControllerProvider.select((AuthState state) => state.session),
    );
    if (session == null) return const ChannelSidebarSnapshot();
    final ChannelSidebarRepository repository = ref.watch(
      channelSidebarRepositoryProvider,
    );
    _session = session;
    _repository = repository;
    return repository.load(session);
  }

  Future<void> refresh() async {
    final AuthSession? session = _session;
    final ChannelSidebarRepository? repository = _repository;
    if (_refreshing || session == null || repository == null) return;
    _refreshing = true;
    final ChannelSidebarSnapshot? current = state.value;
    if (current == null) {
      state = const AsyncLoading<ChannelSidebarSnapshot>();
    } else {
      state = AsyncData(
        current.copyWith(isRefreshing: true, refreshFailed: false),
      );
    }
    try {
      state = AsyncData(await repository.load(session));
    } on Object catch (error, stackTrace) {
      final ChannelSidebarSnapshot? latest = state.value;
      state = latest == null
          ? AsyncError<ChannelSidebarSnapshot>(error, stackTrace)
          : AsyncData(
              latest.copyWith(isRefreshing: false, refreshFailed: true),
            );
    } finally {
      _refreshing = false;
    }
  }
}

Future<void> refreshChannelSidebar(WidgetRef ref) =>
    ref.read(channelSidebarProvider.notifier).refresh();
