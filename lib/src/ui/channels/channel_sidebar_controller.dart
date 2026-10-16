import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/channel_repository.dart';
import 'package:mattermost_flutter/src/ui/channels/selected_channel_controller.dart';

final class ChannelSidebarViewState {
  const ChannelSidebarViewState({
    required this.snapshot,
    this.refreshStatus = const OperationStatus.idle(),
  });

  final ChannelSidebarSnapshot snapshot;
  final OperationStatus refreshStatus;

  ChannelSidebarViewState copyWith({
    ChannelSidebarSnapshot? snapshot,
    OperationStatus? refreshStatus,
  }) => ChannelSidebarViewState(
    snapshot: snapshot ?? this.snapshot,
    refreshStatus: refreshStatus ?? this.refreshStatus,
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
  StreamSubscription<ChannelSidebarRealtimeEvent>? _realtimeSubscription;
  final List<ChannelSidebarRealtimeEvent> _pendingRealtimeEvents =
      <ChannelSidebarRealtimeEvent>[];
  final Set<String> _viewRequests = <String>{};
  bool _refreshing = false;
  bool _recoveryRunning = false;
  bool _recoveryPending = false;
  bool _initialLoadReady = false;
  int _realtimeGeneration = 0;
  String? _activeViewedChannelId;

  @override
  Future<ChannelSidebarViewState> build() async {
    final int generation = ++_realtimeGeneration;
    final AuthSession? session = ref.watch(_sessionProvider);
    final ChannelRepository? repository = session == null
        ? null
        : ref.watch(_repositoryProvider);
    final RequestCancellation cancellation = RequestCancellation();
    _cancellation = cancellation;
    ref.onDispose(() {
      cancellation.cancel();
      _realtimeGeneration += 1;
      unawaited(_cancelRealtime());
    });
    _session = null;
    _repository = null;
    _activeViewedChannelId = null;
    _viewRequests.clear();
    _refreshing = false;
    _recoveryRunning = false;
    _recoveryPending = false;
    _initialLoadReady = false;
    _pendingRealtimeEvents.clear();
    await _cancelRealtime();
    if (session == null || repository == null) {
      return const ChannelSidebarViewState(snapshot: ChannelSidebarSnapshot());
    }
    _session = session;
    _repository = repository;
    ref.listen<SidebarChannel?>(selectedChannelProvider, (
      SidebarChannel? previous,
      SidebarChannel? next,
    ) {
      if (next == null || next.id == _activeViewedChannelId) return;
      final String? previousChannelId = _activeViewedChannelId;
      _activeViewedChannelId = next.id;
      unawaited(
        _markChannelViewed(next.id, previousChannelId: previousChannelId),
      );
    }, fireImmediately: true);
    _startRealtime(session, repository, generation);
    final ChannelSidebarSnapshot loaded = await cancellation.run(
      () => repository.load(session),
    );
    final ChannelSidebarSnapshot reconciled = _applyRealtimeEvents(
      loaded,
      List<ChannelSidebarRealtimeEvent>.of(_pendingRealtimeEvents),
    );
    _pendingRealtimeEvents.clear();
    scheduleMicrotask(() {
      if (generation != _realtimeGeneration) return;
      _initialLoadReady = true;
      _drainRealtimeEvents(generation);
      _startRecoveryIfNeeded(generation);
    });
    return ChannelSidebarViewState(snapshot: reconciled);
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
        current.copyWith(refreshStatus: const OperationStatus.inProgress()),
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
              latest.copyWith(refreshStatus: OperationStatus.failed(error)),
            );
    } finally {
      _refreshing = false;
      _drainRealtimeEvents(_realtimeGeneration);
      _startRecoveryIfNeeded(_realtimeGeneration);
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
    ref
        .read(shellDestinationProvider.notifier)
        .select(ShellDestination.channels);
    ref.read(selectedChannelProvider.notifier).select(channel);
    await refresh();
    ref.read(channelPresentationProvider.notifier).showSelectedChannel();
  }

  void _startRealtime(
    AuthSession session,
    ChannelRepository repository,
    int generation,
  ) {
    if (repository is! ChannelSidebarRealtimeRepository) return;
    final ChannelSidebarRealtimeRepository realtimeRepository =
        repository as ChannelSidebarRealtimeRepository;
    _realtimeSubscription = realtimeRepository
        .watchSidebar(session: session)
        .listen(
          (ChannelSidebarRealtimeEvent event) {
            if (generation != _realtimeGeneration) return;
            _pendingRealtimeEvents.add(event);
            _drainRealtimeEvents(generation);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (generation != _realtimeGeneration) return;
            _pendingRealtimeEvents.add(const ChannelSidebarRefreshRequired());
            _drainRealtimeEvents(generation);
          },
        );
  }

  Future<void> _cancelRealtime() async {
    try {
      await _realtimeSubscription?.cancel();
    } on Object {
      // A closed transport cannot prevent the next session from loading.
    } finally {
      _realtimeSubscription = null;
    }
  }

  void _drainRealtimeEvents(int generation) {
    if (!_initialLoadReady ||
        _refreshing ||
        _recoveryRunning ||
        generation != _realtimeGeneration ||
        _pendingRealtimeEvents.isEmpty) {
      return;
    }
    final ChannelSidebarViewState? current = state.value;
    if (current == null) {
      scheduleMicrotask(() => _drainRealtimeEvents(generation));
      return;
    }
    final List<ChannelSidebarRealtimeEvent> events =
        List<ChannelSidebarRealtimeEvent>.of(_pendingRealtimeEvents);
    _pendingRealtimeEvents.clear();
    final ChannelSidebarSnapshot next = _applyRealtimeEvents(
      current.snapshot,
      events,
    );
    if (!identical(next, current.snapshot)) {
      state = AsyncData(current.copyWith(snapshot: next));
    }
    _startRecoveryIfNeeded(generation);
  }

  ChannelSidebarSnapshot _applyRealtimeEvents(
    ChannelSidebarSnapshot initial,
    List<ChannelSidebarRealtimeEvent> events,
  ) {
    ChannelSidebarSnapshot snapshot = initial;
    for (final ChannelSidebarRealtimeEvent event in events) {
      switch (event) {
        case ChannelSidebarRefreshRequired():
          _recoveryPending = true;
        case ChannelSidebarUnreadChanged(:final channelId, :final isUnread):
          snapshot = _withUnread(snapshot, channelId, isUnread);
        case ChannelSidebarMessagePosted(
          :final channelId,
          :final isThreadReply,
        ):
          final SidebarChannel? channel = _findChannel(snapshot, channelId);
          if (channel == null) {
            _recoveryPending = true;
            continue;
          }
          final String? selectedId = ref.read(selectedChannelProvider)?.id;
          if (selectedId == channelId) {
            unawaited(_markChannelViewed(channelId));
          } else if (!isThreadReply || channel.isDialog) {
            snapshot = _withUnread(snapshot, channelId, true);
          }
      }
    }
    return snapshot;
  }

  SidebarChannel? _findChannel(
    ChannelSidebarSnapshot snapshot,
    String channelId,
  ) {
    for (final SidebarSection section in snapshot.sections) {
      for (final SidebarChannel channel in section.channels) {
        if (channel.id == channelId) return channel;
      }
    }
    return null;
  }

  ChannelSidebarSnapshot _withUnread(
    ChannelSidebarSnapshot snapshot,
    String channelId,
    bool isUnread,
  ) {
    var changed = false;
    final List<SidebarSection> sections = snapshot.sections
        .map((section) {
          var sectionChanged = false;
          final List<SidebarChannel> channels = section.channels
              .map((channel) {
                if (channel.id != channelId || channel.isUnread == isUnread) {
                  return channel;
                }
                changed = true;
                sectionChanged = true;
                return channel.copyWith(isUnread: isUnread);
              })
              .toList(growable: false);
          if (!sectionChanged) return section;
          return SidebarSection(
            id: section.id,
            displayName: section.displayName,
            channels: channels,
            collapsed: section.collapsed,
            muted: section.muted,
            sorting: section.sorting,
          );
        })
        .toList(growable: false);
    return changed ? snapshot.copyWith(sections: sections) : snapshot;
  }

  Future<void> _markChannelViewed(
    String channelId, {
    String? previousChannelId,
  }) async {
    final AuthSession? session = _session;
    final ChannelRepository? repository = _repository;
    if (session == null ||
        repository is! ChannelSidebarRealtimeRepository ||
        !_viewRequests.add(channelId)) {
      return;
    }
    final ChannelSidebarRealtimeRepository realtimeRepository =
        repository as ChannelSidebarRealtimeRepository;
    try {
      await realtimeRepository.markChannelViewed(
        session: session,
        channelId: channelId,
        previousChannelId: previousChannelId,
      );
      final ChannelSidebarViewState? current = state.value;
      if (current != null) {
        final ChannelSidebarSnapshot snapshot = _withUnread(
          current.snapshot,
          channelId,
          false,
        );
        if (!identical(snapshot, current.snapshot)) {
          state = AsyncData(current.copyWith(snapshot: snapshot));
        }
      }
    } on Object {
      // Keep the server-derived state. A later channel_viewed event, manual
      // refresh, or reconnect recovery will reconcile a transient failure.
    } finally {
      _viewRequests.remove(channelId);
    }
  }

  void _startRecoveryIfNeeded(int generation) {
    if (!_recoveryPending ||
        _recoveryRunning ||
        _refreshing ||
        !_initialLoadReady ||
        generation != _realtimeGeneration) {
      return;
    }
    unawaited(_recover(generation));
  }

  Future<void> _recover(int generation) async {
    final AuthSession? session = _session;
    final ChannelRepository? repository = _repository;
    if (session == null || repository == null) return;
    _recoveryRunning = true;
    try {
      while (_recoveryPending && generation == _realtimeGeneration) {
        _recoveryPending = false;
        try {
          final ChannelSidebarSnapshot snapshot = await _cancellation.run(
            () => repository.load(session),
          );
          if (generation != _realtimeGeneration) return;
          final ChannelSidebarViewState? current = state.value;
          if (current != null) {
            state = AsyncData(current.copyWith(snapshot: snapshot));
          }
        } on Object {
          // Preserve the useful snapshot. The next recovery signal or manual
          // refresh will retry without replacing it with an error screen.
        }
      }
    } finally {
      _recoveryRunning = false;
      _drainRealtimeEvents(_realtimeGeneration);
      _startRecoveryIfNeeded(_realtimeGeneration);
    }
  }
}
