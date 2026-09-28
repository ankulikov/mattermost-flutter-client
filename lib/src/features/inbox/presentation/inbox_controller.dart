import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_completeness.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_settings.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/apply_inbox_post_change.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/apply_inbox_thread_change.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/preserve_inbox_snapshot_failures.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_settings_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/use_cases/postpone_thread.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/use_cases/reactivate_postponed_thread.dart';

/// One foreground-only notification produced by a newly received Inbox post.
final class InboxInAppNotification {
  const InboxInAppNotification({
    required this.id,
    required this.author,
    required this.channel,
    this.messagePreview,
  });

  final String id;
  final String author;
  final String channel;

  /// Null unless the user explicitly enabled foreground message previews.
  final String? messagePreview;
}

/// A non-replaying foreground-event channel owned by the authenticated shell.
///
/// It is separate from [InboxSessionController] so a controller rebuild for
/// logout, account switch, or provider invalidation cannot replace the stream
/// a mounted shell is already consuming.
final class InboxInAppNotificationEvents {
  final StreamController<InboxInAppNotification> _controller =
      StreamController<InboxInAppNotification>.broadcast();

  Stream<InboxInAppNotification> get stream => _controller.stream;

  void add(InboxInAppNotification event) => _controller.add(event);

  Future<void> dispose() => _controller.close();
}

/// Injectable scheduling seams for the bounded realtime recovery loop.
///
/// Keeping these in presentation makes retries deterministic in tests without
/// leaking timers, randomness, or a clock into the domain repository contract.
typedef InboxRecoveryBackoff =
    Duration Function({
      required int attempt,
      required DateTime now,
      required double random,
    });

typedef InboxRecoveryDelay = Future<void> Function(Duration duration);

/// Auth-session scoped Inbox projection used by shell badge and realtime UI.
///
/// It deliberately outlives the Inbox page so the authenticated shell can
/// continue to surface new attention while its destination is closed.
final class InboxSessionViewState {
  const InboxSessionViewState({
    required this.snapshot,
    this.refreshStatus = const OperationStatus.idle(),
    this.connectionStatus = InboxConnectionStatus.disconnected,
    this.pendingThreadPostponeSideEffects =
        const <String, PendingPostponeThreadSideEffects>{},
    this.pendingThreadReactivations =
        const <String, PostponedThreadReactivationStatus>{},
  });

  final InboxSnapshot snapshot;
  final OperationStatus refreshStatus;
  final InboxConnectionStatus connectionStatus;
  final Map<String, PendingPostponeThreadSideEffects>
  pendingThreadPostponeSideEffects;
  final Map<String, PostponedThreadReactivationStatus>
  pendingThreadReactivations;

  InboxSessionViewState copyWith({
    InboxSnapshot? snapshot,
    OperationStatus? refreshStatus,
    InboxConnectionStatus? connectionStatus,
    Map<String, PendingPostponeThreadSideEffects>?
    pendingThreadPostponeSideEffects,
    Map<String, PostponedThreadReactivationStatus>? pendingThreadReactivations,
  }) => InboxSessionViewState(
    snapshot: snapshot ?? this.snapshot,
    refreshStatus: refreshStatus ?? this.refreshStatus,
    connectionStatus: connectionStatus ?? this.connectionStatus,
    pendingThreadPostponeSideEffects:
        pendingThreadPostponeSideEffects ??
        this.pendingThreadPostponeSideEffects,
    pendingThreadReactivations:
        pendingThreadReactivations ?? this.pendingThreadReactivations,
  );
}

final class InboxSessionController
    extends AsyncNotifier<InboxSessionViewState> {
  InboxSessionController(
    this._sessionProvider,
    this._inboxProvider,
    this._postponedProvider, {
    Provider<ThreadRepository>? threadProvider,
    Provider<InboxSettingsRepository>? settingsProvider,
    Provider<InboxInAppNotificationEvents>? inAppNotificationEventsProvider,
    DateTime Function()? recoveryClock,
    double Function()? recoveryRandom,
    InboxRecoveryBackoff? recoveryBackoff,
    InboxRecoveryDelay? recoveryDelay,
  }) : _threadProvider = threadProvider,
       _settingsProvider = settingsProvider,
       _inAppNotificationEventsProvider = inAppNotificationEventsProvider,
       _recoveryClock = recoveryClock ?? _defaultRecoveryClock,
       _recoveryRandom = recoveryRandom ?? _defaultRecoveryRandom,
       _recoveryBackoff = recoveryBackoff ?? _defaultRecoveryBackoff,
       _recoveryDelay = recoveryDelay ?? _defaultRecoveryDelay;

  final Provider<AuthSession?> _sessionProvider;
  final Provider<InboxRepository> _inboxProvider;
  final Provider<PostponedRepository> _postponedProvider;
  final Provider<ThreadRepository>? _threadProvider;
  final Provider<InboxSettingsRepository>? _settingsProvider;
  final Provider<InboxInAppNotificationEvents>?
  _inAppNotificationEventsProvider;
  final DateTime Function() _recoveryClock;
  final double Function() _recoveryRandom;
  final InboxRecoveryBackoff _recoveryBackoff;
  final InboxRecoveryDelay _recoveryDelay;
  RequestCancellation? _cancellation;
  RequestCancellation? _refreshCancellation;
  RequestCancellation? _postponedRefreshCancellation;
  RequestCancellation? _recoveryCancellation;
  AuthSession? _session;
  InboxRepository? _inbox;
  PostponedRepository? _postponed;
  StreamSubscription<InboxRealtimeEvent>? _realtimeSubscription;
  static const int _maxBufferedRealtimeEvents = 128;
  final List<InboxRealtimeEvent> _pendingRealtimeEvents =
      <InboxRealtimeEvent>[];
  bool _realtimeBufferOverflowed = false;
  _InboxOperation _operation = _InboxOperation.idle;
  bool _realtimeRefreshQueued = false;
  bool _postponedRefreshQueued = false;
  Future<void>? _recoveryTask;
  bool _recoveryBoundaryObserved = false;
  bool _reconnectTransportRequested = false;
  final Set<String> _reactivatingThreadRoots = <String>{};
  InboxInAppNotificationEvents? _inAppNotificationEvents;
  Future<bool>? _messagePreviewLoad;
  bool _showMessagePreview = false;
  var _messagePreviewRevision = 0;
  Completer<void>? _idleOperation;
  var _buildGeneration = 0;

  static const int _maxRealtimeRecoveryAttempts = 3;

  @override
  Future<InboxSessionViewState> build() async {
    final int generation = ++_buildGeneration;
    _cancellation?.cancel();
    final RequestCancellation cancellation = RequestCancellation();
    _cancellation = cancellation;
    _cancelRealtimeRecovery('Inbox session rebuilt');
    final StreamSubscription<InboxRealtimeEvent>? previousRealtimeSubscription =
        _realtimeSubscription;
    _realtimeSubscription = null;
    await previousRealtimeSubscription?.cancel();
    _pendingRealtimeEvents.clear();
    _realtimeBufferOverflowed = false;
    _reactivatingThreadRoots.clear();
    _messagePreviewLoad = null;
    _showMessagePreview = false;
    _messagePreviewRevision++;
    _operation = _InboxOperation.idle;
    _realtimeRefreshQueued = false;
    _postponedRefreshQueued = false;
    ref.onDispose(() {
      cancellation.cancel();
      _refreshCancellation?.cancel();
      _refreshCancellation = null;
      _postponedRefreshCancellation?.cancel();
      _postponedRefreshCancellation = null;
      _cancelRealtimeRecovery('Inbox session disposed');
      if (generation == _buildGeneration) {
        _buildGeneration += 1;
        unawaited(_realtimeSubscription?.cancel());
      }
    });
    final AuthSession? session = ref.watch(_sessionProvider);
    final Provider<InboxInAppNotificationEvents>? notificationEventsProvider =
        _inAppNotificationEventsProvider;
    _inAppNotificationEvents = notificationEventsProvider == null
        ? null
        : ref.watch(notificationEventsProvider);
    _session = session;
    if (session == null) {
      _inbox = null;
      _postponed = null;
      return InboxSessionViewState(snapshot: InboxSnapshot());
    }
    final InboxRepository inbox = ref.watch(_inboxProvider);
    final PostponedRepository postponed = ref.watch(_postponedProvider);
    _inbox = inbox;
    _postponed = postponed;
    _primeMessagePreviewSetting(session, generation);
    // Subscribe before opening the REST snapshot window. The repository keeps
    // raw signals until its shared context exists; this controller keeps the
    // resulting typed events until the snapshot can be atomically replayed.
    _listenRealtime(session: session, inbox: inbox, generation: generation);
    _operation = _InboxOperation.snapshot;
    try {
      final InboxSnapshot snapshot = await cancellation.run(
        () => inbox.load(session: session),
      );
      if (_cancellation?.isCancelled != false ||
          generation != _buildGeneration) {
        return InboxSessionViewState(snapshot: snapshot);
      }
      final _InboxReplay replay = _drainRealtimeBuffer(
        snapshot: snapshot,
        connectionStatus: InboxConnectionStatus.disconnected,
      );
      _operation = _InboxOperation.idle;
      if (replay.recoveryRequired) {
        _realtimeRefreshQueued = true;
        unawaited(_refreshAfterBuild());
      } else if (replay.postponedRecoveryRequired) {
        _postponedRefreshQueued = true;
        unawaited(_refreshAfterBuild());
      }
      _schedulePostponedThreadReactivationsAfterBuild(replay);
      return InboxSessionViewState(
        snapshot: replay.snapshot,
        connectionStatus: replay.connectionStatus,
      );
    } finally {
      if (_operation == _InboxOperation.snapshot) {
        _operation = _InboxOperation.idle;
      }
    }
  }

  Future<void> _refreshAfterBuild() async {
    await Future<void>.delayed(Duration.zero);
    await _refreshFromRealtime();
  }

  void _schedulePostponedThreadReactivationsAfterBuild(_InboxReplay replay) {
    if (replay.reactivationEvents.isEmpty) return;
    unawaited(
      Future<void>.delayed(Duration.zero, () {
        for (final InboxThreadUpdated event in replay.reactivationEvents) {
          _requestPostponedThreadReactivation(event);
        }
      }),
    );
  }

  void _schedulePostponedThreadReactivations(_InboxReplay replay) {
    for (final InboxThreadUpdated event in replay.reactivationEvents) {
      _requestPostponedThreadReactivation(event);
    }
  }

  void _listenRealtime({
    required AuthSession session,
    required InboxRepository inbox,
    required int generation,
  }) {
    _realtimeSubscription = inbox
        .watch(session: session)
        .listen(
          (InboxRealtimeEvent event) {
            if (generation == _buildGeneration) _onRealtimeEvent(event);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (generation == _buildGeneration) {
              _setConnectionStatus(InboxConnectionStatus.disconnected);
            }
          },
          onDone: () {
            if (generation == _buildGeneration) {
              _setConnectionStatus(InboxConnectionStatus.disconnected);
            }
          },
        );
  }

  /// Replaces a potentially half-open socket and reconciles events missed
  /// while the process was suspended.
  void handleAppResumed() {
    final InboxRepository? inbox = _inbox;
    if (_session == null || inbox == null) return;
    _setConnectionStatus(InboxConnectionStatus.connecting);
    _requestRealtimeRecovery(reconnectTransport: true);
  }

  void _onRealtimeEvent(InboxRealtimeEvent event) {
    if (event case InboxConnectionChanged(:final status)) {
      _setConnectionStatus(status);
      return;
    }
    if (_operation != _InboxOperation.idle) {
      if (_recoveryTask != null) {
        if (_requiresFullRecovery(event)) _recoveryBoundaryObserved = true;
        // The snapshot currently being recovered is authoritative. Deltas
        // observed in this interval are intentionally not retained or
        // replayed: a sequence gap makes their ordering untrustworthy.
        return;
      }
      _bufferRealtimeEvent(event);
      return;
    }
    if (_requiresFullRecovery(event)) {
      _requestRealtimeRecovery();
      return;
    }
    if (_recoveryTask != null) {
      // Do not apply ephemeral live deltas while a recovery snapshot is
      // pending. A successful network-first snapshot supersedes them.
      return;
    }
    final InboxSessionViewState? current = state.value;
    if (current == null) return;
    switch (event) {
      case InboxPostChanged():
        _applyRealtimePostChange(current, event);
      case InboxThreadUpdated() ||
          InboxThreadFollowChanged() ||
          InboxThreadReadChanged():
        _applyRealtimeThreadChange(current, event);
      case InboxRefreshRequired(scope: InboxRefreshScope.postponed):
        _postponedRefreshQueued = true;
        unawaited(_refreshFromRealtime());
      case InboxConnectionChanged() ||
          InboxEligibilityContextChanged() ||
          InboxRefreshRequired(scope: InboxRefreshScope.full):
        return;
      case InboxPreferencesChanged():
        // Unowned preferences must not cause a broad Inbox refresh.
        return;
    }
  }

  void _applyRealtimePostChange(
    InboxSessionViewState current,
    InboxPostChanged change,
  ) {
    final bool wasAlreadyPresent = current.snapshot.newItems.any(
      (InboxItem item) => item.postIds.contains(change.postId),
    );
    final InboxSnapshot snapshot = _applyRealtimePostChangeToSnapshot(
      current.snapshot,
      change,
    );
    final bool wasAdded =
        !wasAlreadyPresent &&
        change.kind == InboxPostChangeKind.created &&
        change.candidate != null &&
        snapshot.newItems.any(
          (InboxItem item) => item.postIds.contains(change.postId),
        );
    final InboxPostCandidate? candidate = change.candidate;
    state = AsyncData(current.copyWith(snapshot: snapshot));
    if (wasAdded && candidate != null) {
      _emitInAppNotification(candidate);
    }
  }

  /// Updates the live foreground privacy gate after its server preference was
  /// saved successfully by the settings form.
  void setShowMessagePreview(bool value) {
    _messagePreviewRevision++;
    _showMessagePreview = value;
    _messagePreviewLoad = Future<bool>.value(value);
  }

  void _emitInAppNotification(InboxPostCandidate candidate) {
    final AuthSession? session = _session;
    final int generation = _buildGeneration;
    if (session == null) return;
    final String message = candidate.post.message;
    final bool showMessagePreview = _showMessagePreview;
    _inAppNotificationEvents?.add(
      InboxInAppNotification(
        id: candidate.post.id,
        author: candidate.post.author.displayName,
        channel: candidate.channel.displayName,
        messagePreview: showMessagePreview && message.isNotEmpty
            ? message
            : null,
      ),
    );
    _primeMessagePreviewSetting(session, generation);
  }

  void _primeMessagePreviewSetting(AuthSession session, int generation) {
    final int revision = _messagePreviewRevision;
    unawaited(
      _loadMessagePreviewSetting(session).then((bool value) {
        if (generation != _buildGeneration ||
            revision != _messagePreviewRevision ||
            !identical(session, _session)) {
          return;
        }
        _showMessagePreview = value;
      }),
    );
  }

  Future<bool> _loadMessagePreviewSetting(AuthSession session) {
    final Future<bool>? existing = _messagePreviewLoad;
    if (existing != null) return existing;
    final InboxSettingsRepository? settings;
    try {
      settings = _inboxSettingsRepository;
    } on Object {
      return Future<bool>.value(_showMessagePreview);
    }
    if (settings == null) return Future<bool>.value(_showMessagePreview);
    final Future<bool> load = _readMessagePreviewSetting(
      settings: settings,
      session: session,
      fallback: _showMessagePreview,
    );
    _messagePreviewLoad = load;
    return load;
  }

  Future<bool> _readMessagePreviewSetting({
    required InboxSettingsRepository settings,
    required AuthSession session,
    required bool fallback,
  }) async {
    try {
      final InboxSettingsSnapshot snapshot = await settings.load(
        session: session,
      );
      return snapshot.settings.inAppNotification.showMessagePreview;
    } on Object {
      return fallback;
    }
  }

  InboxSnapshot _applyRealtimePostChangeToSnapshot(
    InboxSnapshot snapshot,
    InboxPostChanged change,
  ) => applyInboxPostChange(
    snapshot: snapshot,
    postId: change.postId,
    candidate: change.candidate,
    kind: change.kind,
  );

  void _applyRealtimeThreadChange(
    InboxSessionViewState current,
    InboxRealtimeEvent event,
  ) {
    if (event is InboxThreadUpdated &&
        _shouldReactivatePostponedThread(current.snapshot, event)) {
      _requestPostponedThreadReactivation(event);
      return;
    }
    final InboxThreadChangeResult result = applyInboxThreadChange(
      snapshot: current.snapshot,
      event: event,
    );
    state = AsyncData(current.copyWith(snapshot: result.snapshot));
    if (result.recoveryRequired) {
      _realtimeRefreshQueued = true;
      unawaited(_refreshFromRealtime());
    }
  }

  bool _shouldReactivatePostponedThread(
    InboxSnapshot snapshot,
    InboxThreadUpdated event,
  ) =>
      event.candidate?.hasNewExplicitMention == true &&
      snapshot.postponedItems.any(
        (InboxItem item) => item.threadRootIds.contains(event.rootPostId),
      );

  void _requestPostponedThreadReactivation(InboxThreadUpdated event) {
    final String rootPostId = event.rootPostId;
    if (!_reactivatingThreadRoots.add(rootPostId)) return;
    unawaited(
      _reactivatePostponedThread(
        event,
      ).whenComplete(() => _reactivatingThreadRoots.remove(rootPostId)),
    );
  }

  Future<void> _reactivatePostponedThread(InboxThreadUpdated event) async {
    final InboxSessionViewState? current = state.value;
    final AuthSession? session = _session;
    final PostponedRepository? postponed = _postponed;
    final ThreadRepository? threads = _threadRepository;
    final InboxSettingsRepository? settings = _inboxSettingsRepository;
    final InboxThreadCandidate? candidate = event.candidate;
    if (current == null ||
        session == null ||
        postponed == null ||
        threads == null ||
        settings == null ||
        candidate == null) {
      return;
    }
    final PostponedReference? reference = _postponedThreadReference(
      current.snapshot,
      event.rootPostId,
    );
    if (reference == null) return;

    final PostponedThreadReactivationResult result =
        await ReactivatePostponedThread(
          settings: settings,
          postponed: postponed,
          threads: threads,
        )(session: session, teamId: candidate.teamId, reference: reference);
    final InboxSessionViewState? latest = state.value;
    if (latest == null) return;
    if (!result.didReactivate) {
      state = AsyncData(
        latest.copyWith(
          pendingThreadReactivations:
              Map<String, PostponedThreadReactivationStatus>.of(
                latest.pendingThreadReactivations,
              )..[event.rootPostId] = result.status,
        ),
      );
      return;
    }

    // A duplicate/reordered preference event can remove the item while the
    // follow/delete workflow is in flight. Never recreate it from stale
    // content after that authoritative change.
    if (_postponedThreadReference(latest.snapshot, event.rootPostId) == null) {
      return;
    }
    final InboxThreadChangeResult applied = applyInboxThreadChange(
      snapshot: latest.snapshot,
      event: InboxThreadUpdated(
        sequence: event.sequence,
        rootPostId: event.rootPostId,
        channelId: event.channelId,
        unreadReplies: event.unreadReplies,
        unreadMentions: event.unreadMentions,
        // Following was ensured by the workflow; a stale event may still say
        // false because it was emitted before the follow request completed.
        isFollowing: true,
        isInboxEligible: true,
        candidate: candidate,
        reactivatePostponed: true,
      ),
    );
    final Map<String, PostponedThreadReactivationStatus> pending =
        Map<String, PostponedThreadReactivationStatus>.of(
          latest.pendingThreadReactivations,
        )..remove(event.rootPostId);
    state = AsyncData(
      latest.copyWith(
        snapshot: applied.snapshot,
        pendingThreadReactivations: pending,
      ),
    );
  }

  PostponedReference? _postponedThreadReference(
    InboxSnapshot snapshot,
    String rootPostId,
  ) {
    for (final InboxItem item in snapshot.postponedItems) {
      switch (item) {
        case UnavailablePostponedInboxItem(:final reference)
            when reference.kind == PostponedReferenceKind.thread &&
                reference.postId == rootPostId:
          return reference;
        case ThreadInboxItem() when item.thread.id == rootPostId:
          return PostponedReference(
            postId: item.thread.id,
            kind: PostponedReferenceKind.thread,
            addedAt: item.postponedAt ?? item.lastActivityAt,
            targetPostId: item.thread.root.id,
          );
        case ThreadInboxItem():
          continue;
        case ChannelPostInboxItem() || DirectMessageBundleInboxItem():
          continue;
        case UnavailablePostponedInboxItem():
          continue;
      }
    }
    return null;
  }

  void _setConnectionStatus(InboxConnectionStatus status) {
    final InboxSessionViewState? current = state.value;
    if (current == null || current.connectionStatus == status) return;
    state = AsyncData(current.copyWith(connectionStatus: status));
  }

  Future<void> _refreshFromRealtime() async {
    if (_operation != _InboxOperation.idle) return;
    if (_realtimeRefreshQueued) {
      _realtimeRefreshQueued = false;
      _requestRealtimeRecovery();
      return;
    }
    if (_postponedRefreshQueued) {
      _postponedRefreshQueued = false;
      await _reloadPostponedFromRealtime();
    }
  }

  Future<void> _reloadPostponedFromRealtime() async {
    final InboxSessionViewState? current = state.value;
    final AuthSession? session = _session;
    final InboxRepository? inbox = _inbox;
    if (_operation != _InboxOperation.idle ||
        current == null ||
        session == null ||
        inbox == null) {
      return;
    }
    _postponedRefreshCancellation?.cancel('Superseded postponed refresh');
    final RequestCancellation cancellation = RequestCancellation();
    _postponedRefreshCancellation = cancellation;
    _operation = _InboxOperation.postponedRefresh;
    state = AsyncData(
      current.copyWith(refreshStatus: const OperationStatus.inProgress()),
    );
    try {
      final InboxSnapshot snapshot = await cancellation.run(
        () =>
            inbox.reloadPostponed(session: session, current: current.snapshot),
      );
      if (!_isCurrentPostponedRefresh(cancellation)) return;
      final InboxSessionViewState latest = state.value ?? current;
      final _InboxReplay replay = _drainRealtimeBuffer(
        snapshot: snapshot,
        connectionStatus: latest.connectionStatus,
      );
      state = AsyncData(
        latest.copyWith(
          snapshot: replay.snapshot,
          connectionStatus: replay.connectionStatus,
          refreshStatus: const OperationStatus.idle(),
        ),
      );
      _scheduleReplayRecovery(replay);
      _schedulePostponedThreadReactivations(replay);
    } on Object catch (error) {
      if (_isCurrentPostponedRefresh(cancellation) &&
          error is! RequestCancelledException) {
        final InboxSessionViewState latest = state.value ?? current;
        state = AsyncData(
          latest.copyWith(refreshStatus: OperationStatus.failed(error)),
        );
      }
    } finally {
      if (_isCurrentPostponedRefresh(cancellation)) {
        _postponedRefreshCancellation = null;
        _finishBusyOperation();
      }
    }
  }

  /// Retries the complete Inbox projection while preserving already displayed
  /// data throughout the request.
  Future<void> refresh() => _refresh();

  /// Retries an initial snapshot failure through this notifier's own lifecycle.
  ///
  /// A failed initial build has no usable projection for [_refresh] to retain,
  /// so invalidating the notifier is the only safe way to create a new atomic
  /// snapshot window.
  Future<void> retryInitialLoad() async {
    if (state.value != null || _operation != _InboxOperation.idle) return;
    final AuthSession? session = _session;
    final InboxRepository? inbox = _inbox;
    final RequestCancellation? cancellation = _cancellation;
    final int generation = _buildGeneration;
    if (session == null || inbox == null || cancellation == null) return;

    _operation = _InboxOperation.snapshot;
    state = const AsyncLoading<InboxSessionViewState>();
    try {
      final InboxSnapshot snapshot = await cancellation.run(
        () => inbox.load(session: session),
      );
      if (_cancellation != cancellation ||
          cancellation.isCancelled ||
          !_isCurrentGeneration(generation, session)) {
        return;
      }
      final _InboxReplay replay = _drainRealtimeBuffer(
        snapshot: snapshot,
        connectionStatus: InboxConnectionStatus.disconnected,
      );
      state = AsyncData(
        InboxSessionViewState(
          snapshot: replay.snapshot,
          connectionStatus: replay.connectionStatus,
        ),
      );
      _scheduleReplayRecovery(replay);
      _schedulePostponedThreadReactivations(replay);
    } on Object catch (error, stackTrace) {
      if (_cancellation == cancellation &&
          !cancellation.isCancelled &&
          _isCurrentGeneration(generation, session)) {
        state = AsyncError<InboxSessionViewState>(error, stackTrace);
      }
    } finally {
      if (_isCurrentGeneration(generation, session)) {
        _operation = _InboxOperation.idle;
      }
    }
  }

  /// Retries a source reported as incomplete without making presentation know
  /// how that source is loaded. Postponed keeps its narrow server-side reload;
  /// sources without such an implementation fall back to an atomic snapshot.
  Future<void> retrySource(InboxSourceScope scope) =>
      _refresh(sourceScope: scope);

  Future<void> _refresh({InboxSourceScope? sourceScope}) async {
    final InboxSessionViewState? current = state.value;
    final AuthSession? session = _session;
    final InboxRepository? inbox = _inbox;
    if ((_operation != _InboxOperation.idle &&
            _operation != _InboxOperation.refresh) ||
        current == null ||
        session == null ||
        inbox == null) {
      return;
    }
    _refreshCancellation?.cancel('Superseded Inbox refresh');
    final RequestCancellation cancellation = RequestCancellation();
    _refreshCancellation = cancellation;
    _operation = _InboxOperation.refresh;
    state = AsyncData(
      current.copyWith(refreshStatus: const OperationStatus.inProgress()),
    );
    try {
      final InboxSnapshot snapshot = await cancellation.run(
        () => sourceScope == null
            ? inbox.load(session: session)
            : inbox.reloadSource(
                session: session,
                current: current.snapshot,
                scope: sourceScope,
              ),
      );
      if (!_isCurrentRefresh(cancellation)) return;
      final InboxSessionViewState latest = state.value ?? current;
      if (_recoveryTask != null && _recoveryBoundaryObserved) {
        // A transport gap happened while this request was open. Its response
        // cannot safely be layered with the known-incomplete realtime
        // interval, so retain the useful projection until the coalesced retry.
        state = AsyncData(
          latest.copyWith(refreshStatus: const OperationStatus.idle()),
        );
        return;
      }
      final _InboxReplay replay = _drainRealtimeBuffer(
        snapshot: preserveInboxSnapshotFailures(
          previous: current.snapshot,
          incoming: snapshot,
        ),
        connectionStatus: latest.connectionStatus,
      );
      state = AsyncData(
        latest.copyWith(
          snapshot: replay.snapshot,
          connectionStatus: replay.connectionStatus,
          refreshStatus: const OperationStatus.idle(),
        ),
      );
      _scheduleReplayRecovery(replay);
      _schedulePostponedThreadReactivations(replay);
    } on Object catch (error) {
      if (_isCurrentRefresh(cancellation) &&
          error is! RequestCancelledException) {
        final InboxSessionViewState latest = state.value ?? current;
        state = AsyncData(
          latest.copyWith(refreshStatus: OperationStatus.failed(error)),
        );
      }
    } finally {
      _finishRefresh(cancellation);
    }
  }

  bool _isCurrentRefresh(RequestCancellation cancellation) =>
      identical(_refreshCancellation, cancellation) &&
      !cancellation.isCancelled;

  void _finishRefresh(RequestCancellation cancellation) {
    if (!identical(_refreshCancellation, cancellation)) return;
    _refreshCancellation = null;
    _finishBusyOperation();
  }

  bool _isCurrentPostponedRefresh(RequestCancellation cancellation) =>
      identical(_postponedRefreshCancellation, cancellation) &&
      !cancellation.isCancelled;

  void _scheduleReplayRecovery(_InboxReplay replay) {
    if (replay.recoveryRequired) {
      _requestRealtimeRecovery();
    } else if (replay.postponedRecoveryRequired) {
      _postponedRefreshQueued = true;
    }
  }

  bool _requiresFullRecovery(InboxRealtimeEvent event) => switch (event) {
    InboxEligibilityContextChanged() ||
    InboxRefreshRequired(scope: InboxRefreshScope.full) => true,
    _ => false,
  };

  /// Coalesces reconnect, resume and gap signals into a single bounded
  /// recovery state machine. A second boundary while the snapshot is loading
  /// is represented by [_recoveryBoundaryObserved], not another refresh task.
  void _requestRealtimeRecovery({bool reconnectTransport = false}) {
    if (_session == null || _inbox == null) return;
    final bool recoveryAlreadyRunning = _recoveryTask != null;
    _recoveryBoundaryObserved = true;
    _reconnectTransportRequested =
        _reconnectTransportRequested || reconnectTransport;
    if (recoveryAlreadyRunning) return;
    final RequestCancellation cancellation = RequestCancellation();
    final int generation = _buildGeneration;
    _recoveryCancellation = cancellation;
    final Future<void> task = _runRealtimeRecovery(
      cancellation: cancellation,
      generation: generation,
    );
    _recoveryTask = task;
    unawaited(task);
  }

  Future<void> _runRealtimeRecovery({
    required RequestCancellation cancellation,
    required int generation,
  }) async {
    var retryAttempt = 0;
    try {
      while (_isCurrentRecovery(cancellation, generation) &&
          retryAttempt < _maxRealtimeRecoveryAttempts) {
        await _waitUntilIdle(cancellation);
        if (!_isCurrentRecovery(cancellation, generation)) return;

        if (retryAttempt == 0) {
          // Stream controllers normally deliver a burst of reconnect/gap
          // notifications on the next turn. Let that burst coalesce before
          // opening the authoritative REST window.
          await _awaitRecoveryBoundary(
            Future<void>.delayed(Duration.zero),
            cancellation,
          );
          if (!_isCurrentRecovery(cancellation, generation)) return;
        } else {
          final Duration delay = _recoveryBackoff(
            attempt: retryAttempt,
            now: _recoveryClock(),
            random: _recoveryRandom().clamp(0.0, 1.0).toDouble(),
          );
          await _waitForRecoveryDelay(delay, cancellation);
          if (!_isCurrentRecovery(cancellation, generation)) return;
          await _waitUntilIdle(cancellation);
          if (!_isCurrentRecovery(cancellation, generation)) return;
        }

        if (_reconnectTransportRequested) {
          _reconnectTransportRequested = false;
          _inbox?.reconnectRealtime();
        }
        // A gap before the REST request is precisely what this request repairs.
        // Only a boundary during it requires one coalesced follow-up attempt.
        _recoveryBoundaryObserved = false;
        final void Function() detach = cancellation.addListener((
          Object? reason,
        ) {
          _refreshCancellation?.cancel(reason);
        });
        try {
          await refresh();
        } finally {
          detach();
        }
        if (!_isCurrentRecovery(cancellation, generation)) return;
        final InboxSessionViewState? latest = state.value;
        final bool succeeded = latest?.refreshStatus is! OperationFailed;
        if (succeeded && !_recoveryBoundaryObserved) return;
        retryAttempt++;
      }
    } finally {
      final bool isCurrent = _isCurrentRecovery(cancellation, generation);
      if (isCurrent) {
        _recoveryCancellation = null;
        _recoveryTask = null;
        _recoveryBoundaryObserved = false;
        _reconnectTransportRequested = false;
      }
    }
  }

  bool _isCurrentRecovery(RequestCancellation cancellation, int generation) =>
      identical(_recoveryCancellation, cancellation) &&
      !cancellation.isCancelled &&
      generation == _buildGeneration;

  void _cancelRealtimeRecovery(Object reason) {
    _recoveryCancellation?.cancel(reason);
    _recoveryCancellation = null;
    _recoveryTask = null;
    _recoveryBoundaryObserved = false;
    _reconnectTransportRequested = false;
  }

  Future<void> _waitUntilIdle(RequestCancellation cancellation) {
    if (_operation == _InboxOperation.idle) return Future<void>.value();
    final Completer<void> idle = _idleOperation ??= Completer<void>();
    return _awaitRecoveryBoundary(idle.future, cancellation);
  }

  Future<void> _waitForRecoveryDelay(
    Duration delay,
    RequestCancellation cancellation,
  ) => _awaitRecoveryBoundary(_recoveryDelay(delay), cancellation);

  Future<void> _awaitRecoveryBoundary(
    Future<void> operation,
    RequestCancellation cancellation,
  ) async {
    if (cancellation.isCancelled) return;
    final Completer<void> cancelled = Completer<void>();
    final void Function() detach = cancellation.addListener((Object? _) {
      if (!cancelled.isCompleted) cancelled.complete();
    });
    try {
      await Future.any<void>(<Future<void>>[operation, cancelled.future]);
    } finally {
      detach();
    }
  }

  static DateTime _defaultRecoveryClock() => DateTime.now().toUtc();

  static double _defaultRecoveryRandom() => math.Random().nextDouble();

  static Duration _defaultRecoveryBackoff({
    required int attempt,
    required DateTime now,
    required double random,
  }) {
    final int cappedAttempt = math.min(attempt - 1, 5);
    final int baseMilliseconds = 250 * (1 << cappedAttempt);
    final int jitter = (baseMilliseconds * random * 0.5).round();
    return Duration(milliseconds: math.min(15000, baseMilliseconds + jitter));
  }

  static Future<void> _defaultRecoveryDelay(Duration duration) =>
      Future<void>.delayed(duration);

  Future<bool> postpone(InboxItem item) => switch (item) {
    ThreadInboxItem() => _postponeThread(item),
    _ => _move(_latestDirectMessage(item), toPostponed: true),
  };
  Future<bool> remove(InboxItem item) => _move(item, toPostponed: false);

  /// Retries only a CRT thread's post-save work. The durable preference is not
  /// written again, so a retry cannot lose or duplicate the user action.
  Future<bool> retryPostponedThreadSideEffects(String rootPostId) async {
    final InboxSessionViewState? current = state.value;
    final AuthSession? session = _session;
    final ThreadRepository? threads = _threadRepository;
    final PostponedRepository? postponed = _postponed;
    final PendingPostponeThreadSideEffects? pending =
        current?.pendingThreadPostponeSideEffects[rootPostId];
    if (_operation != _InboxOperation.idle ||
        current == null ||
        session == null ||
        postponed == null ||
        threads == null ||
        pending == null) {
      return false;
    }
    final int generation = _buildGeneration;
    _operation = _InboxOperation.move;
    try {
      final PendingPostponeThreadSideEffects result = await PostponeThread(
        postponed: postponed,
        threads: threads,
      ).retry(session: session, pending: pending);
      if (!_isCurrentGeneration(generation, session)) return false;
      final Map<String, PendingPostponeThreadSideEffects> next =
          Map<String, PendingPostponeThreadSideEffects>.of(
            current.pendingThreadPostponeSideEffects,
          );
      if (result.isComplete) {
        next.remove(rootPostId);
      } else {
        next[rootPostId] = result;
      }
      final InboxSessionViewState latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(pendingThreadPostponeSideEffects: next),
      );
      return result.isComplete;
    } on Object {
      return false;
    } finally {
      if (_isCurrentGeneration(generation, session)) _finishBusyOperation();
    }
  }

  InboxItem _latestDirectMessage(InboxItem item) => switch (item) {
    DirectMessageBundleInboxItem(messages: final messages) =>
      DirectMessageBundleInboxItem(
        channelId: item.channelId,
        authorId: item.authorId,
        automationClass: item.automationClass,
        messages: <InboxPostCandidate>[messages.last],
      ),
    _ => item,
  };

  /// Thread operations are read lazily: opening Inbox never constructs a
  /// thread data repository unless the user actually postpones a thread.
  ThreadRepository? get _threadRepository => switch (_threadProvider) {
    final Provider<ThreadRepository> provider => ref.read(provider),
    null => null,
  };

  InboxSettingsRepository? get _inboxSettingsRepository =>
      switch (_settingsProvider) {
        final Provider<InboxSettingsRepository> provider => ref.read(provider),
        null => null,
      };

  Future<bool> _postponeThread(ThreadInboxItem item) async {
    final InboxSessionViewState? current = state.value;
    final AuthSession? session = _session;
    final PostponedRepository? postponed = _postponed;
    final ThreadRepository? threads = _threadRepository;
    if (_operation != _InboxOperation.idle ||
        current == null ||
        session == null ||
        postponed == null ||
        threads == null) {
      return false;
    }
    final int generation = _buildGeneration;
    _operation = _InboxOperation.move;
    final DateTime addedAt = DateTime.now().toUtc();
    try {
      final PendingPostponeThreadSideEffects result = await PostponeThread(
        postponed: postponed,
        threads: threads,
      )(session: session, item: item, addedAt: addedAt);
      if (!_isCurrentGeneration(generation, session)) return false;
      final List<InboxItem> newItems = List<InboxItem>.of(
        current.snapshot.newItems,
      );
      final List<InboxItem> postponedItems = List<InboxItem>.of(
        current.snapshot.postponedItems,
      );
      _removePostIds(newItems, item);
      postponedItems.add(_withPostponedAt(item, result.reference.addedAt));
      final Map<String, PendingPostponeThreadSideEffects> pending =
          Map<String, PendingPostponeThreadSideEffects>.of(
            current.pendingThreadPostponeSideEffects,
          );
      if (result.isComplete) {
        pending.remove(item.thread.id);
      } else {
        pending[item.thread.id] = result;
      }
      final InboxSessionViewState latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          snapshot: InboxSnapshot(
            newItems: newItems,
            postponedItems: postponedItems,
            builtAt: current.snapshot.builtAt,
            completeness: current.snapshot.completeness,
            diagnosticsCodes: current.snapshot.diagnosticsCodes,
            sourceFailures: current.snapshot.sourceFailures,
          ),
          refreshStatus: const OperationStatus.idle(),
          pendingThreadPostponeSideEffects: pending,
        ),
      );
      // The queue movement is successful once the preference is durable. A
      // non-empty result remains visible and can be retried independently.
      return true;
    } on Object {
      return false;
    } finally {
      if (_isCurrentGeneration(generation, session)) _finishBusyOperation();
    }
  }

  /// Removes an unfollowed CRT thread from both volatile Inbox queues.
  void removeUnfollowedThread(String rootPostId) {
    final InboxSessionViewState? current = state.value;
    if (current == null) return;
    List<InboxItem> withoutThread(Iterable<InboxItem> items) => items
        .where(
          (InboxItem item) =>
              item is! ThreadInboxItem || item.thread.id != rootPostId,
        )
        .toList(growable: false);
    state = AsyncData(
      current.copyWith(
        snapshot: InboxSnapshot(
          newItems: withoutThread(current.snapshot.newItems),
          postponedItems: withoutThread(current.snapshot.postponedItems),
          builtAt: current.snapshot.builtAt,
          completeness: current.snapshot.completeness,
          diagnosticsCodes: current.snapshot.diagnosticsCodes,
          sourceFailures: current.snapshot.sourceFailures,
        ),
      ),
    );
  }

  Future<bool> markRead(InboxItem item) async {
    final InboxSessionViewState? current = state.value;
    final AuthSession? session = _session;
    final InboxRepository? inbox = _inbox;
    if (_operation != _InboxOperation.idle ||
        current == null ||
        session == null ||
        inbox == null) {
      return false;
    }
    final int generation = _buildGeneration;
    _operation = _InboxOperation.markRead;
    try {
      await inbox.markRead(session: session, item: item);
      if (!_isCurrentGeneration(generation, session)) return false;
      final List<InboxItem> newItems = current.snapshot.newItems
          .where((InboxItem candidate) => !_isReadBy(candidate, item))
          .toList(growable: false);
      final InboxSessionViewState latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          snapshot: InboxSnapshot(
            newItems: newItems,
            postponedItems: current.snapshot.postponedItems,
            builtAt: current.snapshot.builtAt,
            completeness: current.snapshot.completeness,
            diagnosticsCodes: current.snapshot.diagnosticsCodes,
            sourceFailures: current.snapshot.sourceFailures,
          ),
          refreshStatus: const OperationStatus.idle(),
        ),
      );
      return true;
    } on Object {
      return false;
    } finally {
      if (_isCurrentGeneration(generation, session)) _finishBusyOperation();
    }
  }

  bool _isReadBy(InboxItem candidate, InboxItem readItem) {
    if (readItem is ThreadInboxItem) return candidate.key == readItem.key;
    final String channelId = switch (readItem) {
      ChannelPostInboxItem(:final post) => post.channelId,
      DirectMessageBundleInboxItem(:final channelId) => channelId,
      ThreadInboxItem() => '',
      UnavailablePostponedInboxItem() => '',
    };
    return switch (candidate) {
      ChannelPostInboxItem(:final post) => post.channelId == channelId,
      DirectMessageBundleInboxItem(channelId: final candidateChannelId) =>
        candidateChannelId == channelId,
      ThreadInboxItem() => false,
      UnavailablePostponedInboxItem() => false,
    };
  }

  Future<bool> _move(InboxItem item, {required bool toPostponed}) async {
    final InboxSessionViewState? current = state.value;
    final AuthSession? session = _session;
    final InboxRepository? inbox = _inbox;
    final PostponedRepository? postponed = _postponed;
    if (_operation != _InboxOperation.idle ||
        current == null ||
        session == null ||
        inbox == null ||
        postponed == null) {
      return false;
    }
    final int generation = _buildGeneration;
    _operation = _InboxOperation.move;
    final DateTime now = DateTime.now().toUtc();
    final PostponedReferenceKind kind = item is ThreadInboxItem
        ? PostponedReferenceKind.thread
        : PostponedReferenceKind.post;
    final List<PostponedReference> references =
        item is UnavailablePostponedInboxItem
        ? <PostponedReference>[item.reference]
        : item.postIds
              .map(
                (String id) =>
                    PostponedReference(postId: id, kind: kind, addedAt: now),
              )
              .toList(growable: false);
    try {
      final PostponedBatchOutcome outcome = toPostponed
          ? await postponed.saveWithOutcome(
              session: session,
              references: references,
            )
          : await postponed.removeWithOutcome(
              session: session,
              references: references,
            );
      if (!_isCurrentGeneration(generation, session)) return false;
      if (outcome.requiresReconciliation) {
        return await _reconcilePostponedMutation(
          current: current,
          session: session,
          inbox: inbox,
          generation: generation,
        );
      }
      final List<InboxItem> newItems = List<InboxItem>.of(
        current.snapshot.newItems,
      );
      final List<InboxItem> postponedItems = List<InboxItem>.of(
        current.snapshot.postponedItems,
      );
      if (toPostponed) {
        _removePostIds(newItems, item);
        postponedItems.add(_withPostponedAt(item, now));
      } else {
        _removePostIds(postponedItems, item);
      }
      final InboxSessionViewState latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          snapshot: InboxSnapshot(
            newItems: newItems,
            postponedItems: postponedItems,
            builtAt: current.snapshot.builtAt,
            completeness: current.snapshot.completeness,
            diagnosticsCodes: current.snapshot.diagnosticsCodes,
            sourceFailures: current.snapshot.sourceFailures,
          ),
          refreshStatus: const OperationStatus.idle(),
        ),
      );
      return true;
    } on Object {
      return false;
    } finally {
      if (_isCurrentGeneration(generation, session)) _finishBusyOperation();
    }
  }

  /// Replaces a local queue guess with the hydrated, authoritative server
  /// preference source after a partial multi-batch preference mutation.
  ///
  /// The action still returns false: the requested operation did not complete
  /// as a whole, but the projection accurately shows the confirmed server
  /// state. A failed scoped reload intentionally leaves useful local data in
  /// place instead of removing every selected item optimistically.
  Future<bool> _reconcilePostponedMutation({
    required InboxSessionViewState current,
    required AuthSession session,
    required InboxRepository inbox,
    required int generation,
  }) async {
    try {
      final InboxSnapshot reconciled = await inbox.reloadPostponed(
        session: session,
        current: current.snapshot,
      );
      if (!_isCurrentGeneration(generation, session)) return false;
      final bool postponedSourceFailed = reconciled.sourceFailures.any(
        (InboxSourceFailure failure) =>
            failure.scope == InboxSourceScope.postponed,
      );
      if (postponedSourceFailed) return false;
      final InboxSessionViewState latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          snapshot: reconciled,
          refreshStatus: const OperationStatus.idle(),
        ),
      );
    } on Object {
      return false;
    }
    return false;
  }

  bool _isCurrentGeneration(int generation, AuthSession session) =>
      generation == _buildGeneration && identical(session, _session);

  void _finishBusyOperation() {
    _operation = _InboxOperation.idle;
    final Completer<void>? waitingForIdle = _idleOperation;
    _idleOperation = null;
    if (waitingForIdle != null && !waitingForIdle.isCompleted) {
      waitingForIdle.complete();
    }
    final InboxSessionViewState? current = state.value;
    if (current != null &&
        (_pendingRealtimeEvents.isNotEmpty || _realtimeBufferOverflowed)) {
      final _InboxReplay replay = _drainRealtimeBuffer(
        snapshot: current.snapshot,
        connectionStatus: current.connectionStatus,
      );
      state = AsyncData(
        current.copyWith(
          snapshot: replay.snapshot,
          connectionStatus: replay.connectionStatus,
        ),
      );
      _scheduleReplayRecovery(replay);
      _schedulePostponedThreadReactivations(replay);
    }
    if (_realtimeRefreshQueued || _postponedRefreshQueued) {
      unawaited(_refreshFromRealtime());
    }
  }

  void _bufferRealtimeEvent(InboxRealtimeEvent event) {
    if (_realtimeBufferOverflowed) return;
    if (_pendingRealtimeEvents.length == _maxBufferedRealtimeEvents) {
      _pendingRealtimeEvents.clear();
      _realtimeBufferOverflowed = true;
      return;
    }
    _pendingRealtimeEvents.add(event);
  }

  _InboxReplay _drainRealtimeBuffer({
    required InboxSnapshot snapshot,
    required InboxConnectionStatus connectionStatus,
  }) {
    final List<InboxRealtimeEvent> buffered = List<InboxRealtimeEvent>.of(
      _pendingRealtimeEvents,
    );
    _pendingRealtimeEvents.clear();
    final bool overflowed = _realtimeBufferOverflowed;
    _realtimeBufferOverflowed = false;
    final List<InboxRealtimeEvent> sequenced =
        buffered.where(_hasSequence).toList(growable: false)..sort(
          (InboxRealtimeEvent left, InboxRealtimeEvent right) =>
              (left as InboxSequencedRealtimeEvent).sequence.compareTo(
                (right as InboxSequencedRealtimeEvent).sequence,
              ),
        );
    final List<InboxRealtimeEvent> unsequenced = buffered
        .where((InboxRealtimeEvent event) => !_hasSequence(event))
        .toList(growable: false);
    InboxSnapshot replayedSnapshot = snapshot;
    InboxConnectionStatus replayedConnectionStatus = connectionStatus;
    final bool hasAuthoritativeRecoveryBoundary =
        overflowed || buffered.any(_eventMakesProjectionIncomplete);
    if (hasAuthoritativeRecoveryBoundary) {
      // A gap is an authoritative boundary, not a delta to merge. In
      // particular, do not apply events that happen to precede/follow it in a
      // local buffer; either side can belong to an incomplete transport view.
      for (final InboxRealtimeEvent event in buffered) {
        if (event case InboxConnectionChanged(:final status)) {
          replayedConnectionStatus = status;
        }
      }
      return _InboxReplay(
        snapshot: replayedSnapshot,
        connectionStatus: replayedConnectionStatus,
        recoveryRequired: true,
        postponedRecoveryRequired: false,
      );
    }
    bool recoveryRequired = false;
    bool postponedRecoveryRequired = false;
    final List<InboxThreadUpdated> reactivationEvents = <InboxThreadUpdated>[];
    for (final InboxRealtimeEvent event in <InboxRealtimeEvent>[
      ...unsequenced,
      ...sequenced,
    ]) {
      switch (event) {
        case InboxConnectionChanged(:final status):
          replayedConnectionStatus = status;
        case InboxPostChanged():
          replayedSnapshot = _applyRealtimePostChangeToSnapshot(
            replayedSnapshot,
            event,
          );
        case InboxThreadUpdated()
            when _shouldReactivatePostponedThread(replayedSnapshot, event):
          reactivationEvents.add(event);
        case InboxThreadUpdated() ||
            InboxThreadFollowChanged() ||
            InboxThreadReadChanged():
          final InboxThreadChangeResult result = applyInboxThreadChange(
            snapshot: replayedSnapshot,
            event: event,
          );
          replayedSnapshot = result.snapshot;
          recoveryRequired = recoveryRequired || result.recoveryRequired;
        case InboxEligibilityContextChanged() ||
            InboxRefreshRequired(scope: InboxRefreshScope.full):
          recoveryRequired = true;
        case InboxRefreshRequired(scope: InboxRefreshScope.postponed):
          postponedRecoveryRequired = true;
        case InboxPreferencesChanged():
          continue;
      }
    }
    return _InboxReplay(
      snapshot: replayedSnapshot,
      connectionStatus: replayedConnectionStatus,
      recoveryRequired: recoveryRequired,
      postponedRecoveryRequired: postponedRecoveryRequired,
      reactivationEvents: reactivationEvents,
    );
  }

  bool _hasSequence(InboxRealtimeEvent event) => switch (event) {
    InboxSequencedRealtimeEvent(:final sequence) => sequence > 0,
    _ => false,
  };

  bool _eventMakesProjectionIncomplete(InboxRealtimeEvent event) =>
      switch (event) {
        InboxEligibilityContextChanged() ||
        InboxRefreshRequired(scope: InboxRefreshScope.full) ||
        InboxThreadUpdated(recoveryRequired: true) ||
        InboxThreadFollowChanged(recoveryRequired: true) => true,
        _ => false,
      };

  void _removePostIds(List<InboxItem> items, InboxItem removed) {
    final Set<String> removedIds = removed.postIds.toSet();
    for (var index = items.length - 1; index >= 0; index--) {
      final InboxItem current = items[index];
      if (current is DirectMessageBundleInboxItem) {
        final Set<String> retainedIds = current.postIds.toSet()
          ..removeAll(removedIds);
        if (retainedIds.length == current.postIds.length) continue;
        if (retainedIds.isEmpty) {
          items.removeAt(index);
        } else {
          items[index] = current.retainingPostIds(retainedIds);
        }
      } else if (current.postIds.any(removedIds.contains)) {
        items.removeAt(index);
      }
    }
  }

  InboxItem _withPostponedAt(InboxItem item, DateTime at) => switch (item) {
    ThreadInboxItem() => ThreadInboxItem(
      thread: item.thread,
      channel: item.channel,
      teamId: item.teamId,
      rootAttentionReason: item.rootAttentionReason,
      reactivatesPostponed: item.reactivatesPostponed,
      postponedAt: at,
    ),
    ChannelPostInboxItem() => ChannelPostInboxItem(
      candidate: item.candidate,
      postponedAt: at,
    ),
    DirectMessageBundleInboxItem() => DirectMessageBundleInboxItem(
      channelId: item.channelId,
      authorId: item.authorId,
      automationClass: item.automationClass,
      messages: item.messages,
      postponedAt: at,
    ),
    UnavailablePostponedInboxItem() => item,
  };
}

enum _InboxOperation {
  idle,
  snapshot,
  refresh,
  postponedRefresh,
  markRead,
  move,
}

final class _InboxReplay {
  const _InboxReplay({
    required this.snapshot,
    required this.connectionStatus,
    required this.recoveryRequired,
    required this.postponedRecoveryRequired,
    this.reactivationEvents = const <InboxThreadUpdated>[],
  });

  final InboxSnapshot snapshot;
  final InboxConnectionStatus connectionStatus;
  final bool recoveryRequired;
  final bool postponedRecoveryRequired;
  final List<InboxThreadUpdated> reactivationEvents;
}

/// Backward-compatible name while Inbox callers migrate to the explicit
/// session projection terminology.
@Deprecated('Use InboxSessionViewState instead.')
typedef InboxViewState = InboxSessionViewState;

/// Backward-compatible controller name for focused controller tests.
@Deprecated('Use InboxSessionController instead.')
typedef InboxController = InboxSessionController;
