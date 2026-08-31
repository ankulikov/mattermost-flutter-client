import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/channel_repository.dart';
import 'package:mattermost_flutter/src/ui/channels/selected_channel_controller.dart';

final class ChannelSidebarViewState {
  const ChannelSidebarViewState({
    required this.snapshot,
    this.isRefreshing = false,
    this.refreshFailed = false,
  });

  final ChannelSidebarSnapshot snapshot;
  final bool isRefreshing;
  final bool refreshFailed;

  ChannelSidebarViewState copyWith({
    ChannelSidebarSnapshot? snapshot,
    bool? isRefreshing,
    bool? refreshFailed,
  }) => ChannelSidebarViewState(
    snapshot: snapshot ?? this.snapshot,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    refreshFailed: refreshFailed ?? this.refreshFailed,
  );
}

final class ChannelSidebarController
    extends AsyncNotifier<ChannelSidebarViewState> {
  ChannelSidebarController(this._sessionProvider, this._repositoryProvider);

  final Provider<AuthSession?> _sessionProvider;
  final Provider<ChannelRepository> _repositoryProvider;
  late RequestCancellation _cancellation;
  AuthSession? _session;
  ChannelRepository? _repository;
  bool _refreshing = false;

  @override
  Future<ChannelSidebarViewState> build() async {
    final RequestCancellation cancellation = RequestCancellation();
    _cancellation = cancellation;
    ref.onDispose(cancellation.cancel);
    _session = null;
    _repository = null;
    final AuthSession? session = ref.watch(_sessionProvider);
    if (session == null) {
      return const ChannelSidebarViewState(snapshot: ChannelSidebarSnapshot());
    }
    final ChannelRepository repository = ref.watch(_repositoryProvider);
    _session = session;
    _repository = repository;
    return ChannelSidebarViewState(
      snapshot: await cancellation.run(() => repository.load(session)),
    );
  }

  Future<void> refresh() async {
    final AuthSession? session = _session;
    final ChannelRepository? repository = _repository;
    if (_refreshing || session == null || repository == null) return;
    final RequestCancellation cancellation = _cancellation;
    _refreshing = true;
    final ChannelSidebarViewState? current = state.value;
    if (current == null) {
      state = const AsyncLoading<ChannelSidebarViewState>();
    } else {
      state = AsyncData(
        current.copyWith(isRefreshing: true, refreshFailed: false),
      );
    }
    try {
      state = AsyncData(
        ChannelSidebarViewState(
          snapshot: await cancellation.run(() => repository.load(session)),
        ),
      );
    } on Object catch (error, stackTrace) {
      if (cancellation.isCancelled) return;
      final ChannelSidebarViewState? latest = state.value;
      state = latest == null
          ? AsyncError<ChannelSidebarViewState>(error, stackTrace)
          : AsyncData(
              latest.copyWith(isRefreshing: false, refreshFailed: true),
            );
    } finally {
      _refreshing = false;
    }
  }

  Future<void> openDirectMessage(UserProfile profile) async {
    final AuthSession? session = _session;
    final ChannelRepository? repository = _repository;
    if (session == null || repository == null) {
      throw StateError('Channel navigation is not ready');
    }
    final SidebarChannel channel = await _cancellation.run(
      () => repository.openDirectMessage(
        currentUserId: session.userId,
        otherUserId: profile.id,
        otherUserDisplayName: profile.fullName,
      ),
    );
    ref.read(threadsDestinationProvider.notifier).clear();
    ref.read(selectedChannelProvider.notifier).select(channel);
    await refresh();
  }
}
