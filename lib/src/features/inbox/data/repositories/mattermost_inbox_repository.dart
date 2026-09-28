import 'dart:async';
import 'dart:convert';

import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/user_mapper.dart';
import 'package:mattermost_flutter/src/data/realtime/session_realtime_service.dart';
import 'package:mattermost_flutter/src/data/realtime/websocket_gateway.dart';
import 'package:mattermost_flutter/src/data/storage/credential_store.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/message_mapper.dart';
import 'package:mattermost_flutter/src/features/inbox/data/inbox_context_loader.dart';
import 'package:mattermost_flutter/src/features/inbox/data/inbox_snapshot_sources.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_completeness.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_notification_settings.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_settings.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_source_result.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/assemble_inbox_projection.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/classify_inbox_attention.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/notification_eligibility.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/reconcile_queues.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_settings_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';

/// Network-first Inbox snapshot builder and realtime event mapper.
///
/// Connection lifecycle stays in [WebSocketGateway], while this repository
/// maps transport events into the same domain candidates used by REST.
final class MattermostInboxRepository extends InboxRepository {
  MattermostInboxRepository({
    required MattermostApi api,
    required MessageMapper<MattermostPostDto, UserSummary> messageMapper,
    required PostponedRepository postponed,
    InboxSettingsRepository? settings,
    WebSocketGateway? webSocketGateway,
    CredentialStore? credentialStore,
    SessionRealtimeService? realtime,
    DateTime Function()? now,
  }) : _api = api,
       _messageMapper = messageMapper,
       _contextLoader = InboxContextLoader(api: api),
       _snapshotSources = <InboxSnapshotSource>[
         InboxFollowedThreadsSource(api: api),
         InboxUnreadChannelPostsSource(api: api),
         InboxPostponedSource(api: api, postponed: postponed),
       ],
       _postponedSource = InboxPostponedSource(api: api, postponed: postponed),
       _settings = settings,
       _realtime =
           realtime ??
           (webSocketGateway != null && credentialStore != null
               ? SessionRealtimeService(
                   gateway: webSocketGateway,
                   credentialStore: credentialStore,
                 )
               : null),
       _now = now ?? DateTime.now;

  final MattermostApi _api;
  final MessageMapper<MattermostPostDto, UserSummary> _messageMapper;
  final InboxContextLoader _contextLoader;
  final List<InboxSnapshotSource> _snapshotSources;
  final InboxProjectionAssembler _projectionAssembler =
      const InboxProjectionAssembler();
  final InboxPostponedSource _postponedSource;
  final InboxSettingsRepository? _settings;
  final SessionRealtimeService? _realtime;
  final DateTime Function() _now;
  _InboxRealtimeScope? _realtimeScope;
  InboxSnapshotContext? _snapshotContext;
  final Set<_InboxRealtimeWatch> _realtimeWatches = <_InboxRealtimeWatch>{};

  static const Set<String> _realtimeEventNames = <String>{
    'posted',
    'post_edited',
    'post_deleted',
    'post_unread',
    'thread_updated',
    'thread_follow_changed',
    'thread_read_changed',
    'channel_viewed',
    'channel_member_updated',
    'direct_added',
    'group_added',
    'user_updated',
    'preference_changed',
    'preferences_changed',
    'preferences_deleted',
  };
  static const String _postponedPreferenceCategory = 'postponed_messages';
  static const int _maxEmbeddedRealtimeJsonCharacters = 64 * 1024;

  @override
  Future<InboxSnapshot> load({required AuthSession session}) =>
      _retryRateLimited(() => _loadSnapshot(session: session));

  Future<InboxSnapshot> _loadSnapshot({required AuthSession session}) async {
    final DateTime builtAt = _now();
    final Future<InboxSettings> settings = _loadSettings(session);
    _rawUsersAreBots.clear();
    final InboxSnapshotContext context = await _contextLoader.load(
      session: session,
    );
    _snapshotContext = context;
    // The controller opens its SessionRealtimeService subscription before the
    // REST request. Once the shared context is ready, buffered transport
    // events can be mapped while the remaining snapshot sources are loading.
    final _InboxRealtimeScope realtimeScope = _InboxRealtimeScope(
      currentUser: context.currentUser,
      channels: context.channels,
      members: context.members,
      authors: <String, UserSummary>{},
    );
    _realtimeScope = realtimeScope;
    for (final _InboxRealtimeWatch watch in _realtimeWatches) {
      watch.flushScopeBuffer();
    }
    final InboxSourceMapper mapper = InboxSourceMapper(
      api: _api,
      messageMapper: _messageMapper,
    );
    final List<InboxSourceResult> sources = <InboxSourceResult>[];
    for (final InboxSnapshotSource source in _snapshotSources) {
      try {
        sources.add(
          await _retryRateLimited(
            () =>
                source.load(session: session, context: context, mapper: mapper),
          ),
        );
      } on RequestCancelledException {
        rethrow;
      } on Object {
        if (RequestCancellation.current
            case final RequestCancellation cancellation
            when cancellation.isCancelled) {
          throw RequestCancelledException(cancellation.reason);
        }
        sources.add(
          InboxSourceResult(
            candidates: InboxSourceSnapshot(),
            completeness: InboxCompleteness.truncated,
            diagnosticsCodes: const <InboxSourceDiagnosticCode>[
              InboxSourceDiagnosticCode.sourceRequestFailed,
            ],
            sourceFailures: <InboxSourceFailure>[
              InboxSourceFailure(scope: source.scope),
            ],
          ),
        );
      }
    }
    _rawUsersAreBots.addAll(mapper.rawUsersAreBots);
    realtimeScope.authors.addAll(mapper.authors);
    final InboxSnapshot result = _projectionAssembler.assemble(
      sources: sources,
      builtAt: builtAt,
      directGrouping: (await settings).directGrouping,
    );
    return result;
  }

  Future<InboxSettings> _loadSettings(AuthSession session) async {
    final InboxSettingsRepository? settings = _settings;
    if (settings == null) return InboxSettings.defaults;
    try {
      return (await settings.load(session: session)).settings;
    } on Object {
      // Client settings must never make the server-backed Inbox unavailable.
      // Defaults retain the desktop-authoritative projection without logging
      // any preference payload.
      return InboxSettings.defaults;
    }
  }

  @override
  Future<InboxSnapshot> reloadPostponed({
    required AuthSession session,
    required InboxSnapshot current,
  }) async {
    final InboxSnapshotContext? context = _snapshotContext;
    if (context == null) return load(session: session);
    final InboxSourceMapper mapper = InboxSourceMapper(
      api: _api,
      messageMapper: _messageMapper,
    );
    late final InboxSourceResult source;
    try {
      source = await _retryRateLimited(
        () => _postponedSource.load(
          session: session,
          context: context,
          mapper: mapper,
        ),
      );
    } on RequestCancelledException {
      rethrow;
    } on Object {
      source = InboxSourceResult(
        candidates: InboxSourceSnapshot(),
        completeness: InboxCompleteness.truncated,
        diagnosticsCodes: const <InboxSourceDiagnosticCode>[
          InboxSourceDiagnosticCode.sourceRequestFailed,
        ],
        sourceFailures: const <InboxSourceFailure>[
          InboxSourceFailure(scope: InboxSourceScope.postponed),
        ],
      );
    }
    return _mergePostponedSource(current: current, source: source);
  }

  InboxSnapshot _mergePostponedSource({
    required InboxSnapshot current,
    required InboxSourceResult source,
  }) {
    final bool failed = source.sourceFailures.any(
      (InboxSourceFailure failure) =>
          failure.scope == InboxSourceScope.postponed,
    );
    final bool hasOtherSourceFailure = current.sourceFailures.any(
      (InboxSourceFailure failure) =>
          failure.scope != InboxSourceScope.postponed,
    );
    final InboxSnapshot queues = reconcileQueues(
      newItems: current.newItems,
      postponedItems: failed ? current.postponedItems : source.postponedItems,
      builtAt: current.builtAt,
    );
    return InboxSnapshot(
      newItems: queues.newItems,
      postponedItems: queues.postponedItems,
      builtAt: current.builtAt,
      completeness: InboxCompleteness.mostLimited(<InboxCompleteness>[
        current.completeness,
        source.completeness,
      ]),
      diagnosticsCodes: <InboxSourceDiagnosticCode>{
        ...current.diagnosticsCodes.where(
          (InboxSourceDiagnosticCode code) =>
              code != InboxSourceDiagnosticCode.postponedHydrationUnavailable &&
              (code != InboxSourceDiagnosticCode.sourceRequestFailed ||
                  hasOtherSourceFailure),
        ),
        ...source.diagnosticsCodes,
      },
      sourceFailures: <InboxSourceFailure>{
        ...current.sourceFailures.where(
          (InboxSourceFailure failure) =>
              failure.scope != InboxSourceScope.postponed,
        ),
        ...source.sourceFailures,
      },
    );
  }

  /// Retries one server rate limit at a time. The retry budget is deliberately
  /// small: a foreground snapshot remains cancelable and never becomes an
  /// unbounded background sync loop.
  Future<T> _retryRateLimited<T>(Future<T> Function() request) async {
    const int maxRateLimitRetries = 1;
    for (var attempt = 0; ; attempt++) {
      _throwIfCancelled();
      try {
        return await request();
      } on MattermostRateLimitException catch (error) {
        if (attempt >= maxRateLimitRetries) rethrow;
        await _waitForRateLimit(error.retryAfter, attempt: attempt);
      }
    }
  }

  Future<void> _waitForRateLimit(Duration? retryAfter, {required int attempt}) {
    final Duration delay =
        retryAfter ?? Duration(milliseconds: 250 * (1 << attempt));
    final RequestCancellation? cancellation = RequestCancellation.current;
    if (cancellation == null) return Future<void>.delayed(delay);
    if (cancellation.isCancelled) {
      return Future<void>.error(RequestCancelledException(cancellation.reason));
    }
    final Completer<void> completed = Completer<void>();
    Timer? timer;
    final void Function() detach = cancellation.addListener((Object? reason) {
      timer?.cancel();
      if (!completed.isCompleted) {
        completed.completeError(RequestCancelledException(reason));
      }
    });
    timer = Timer(delay, () {
      detach();
      if (!completed.isCompleted) completed.complete();
    });
    if (completed.isCompleted) timer.cancel();
    return completed.future;
  }

  void _throwIfCancelled() {
    final RequestCancellation? cancellation = RequestCancellation.current;
    if (cancellation?.isCancelled == true) {
      throw RequestCancelledException(cancellation!.reason);
    }
  }

  @override
  Stream<InboxRealtimeEvent> watch({required AuthSession session}) {
    final SessionRealtimeService? realtime = _realtime;
    if (realtime == null) return const Stream<InboxRealtimeEvent>.empty();
    late final _InboxRealtimeWatch watch;
    watch = _InboxRealtimeWatch(
      signals: realtime.watch(
        session: session,
        eventNames: _realtimeEventNames,
        // A known event for a channel absent from the current context needs a
        // bounded recovery. Filtering it out here would silently lose the
        // only signal that a DM/GM or membership scope changed.
        acceptsChannel: (_) => true,
      ),
      isScopeReady: () => _realtimeScope != null,
      mapConnectionStatus: _mapConnectionStatus,
      mapEvent: (MattermostWebSocketEvent event) =>
          _mapRealtimeEvent(session, event),
      onClosed: () => _realtimeWatches.remove(watch),
    );
    _realtimeWatches.add(watch);
    return watch.stream;
  }

  @override
  void reconnectRealtime() {
    _realtime?.reconnect();
  }

  InboxConnectionStatus _mapConnectionStatus(
    WebSocketConnectionStatus status,
  ) => switch (status) {
    WebSocketConnectionStatus.connecting => InboxConnectionStatus.connecting,
    WebSocketConnectionStatus.connected => InboxConnectionStatus.connected,
    WebSocketConnectionStatus.disconnected =>
      InboxConnectionStatus.disconnected,
  };

  Future<InboxRealtimeEvent?> _mapRealtimeEvent(
    AuthSession session,
    MattermostWebSocketEvent event,
  ) async {
    switch (event.name) {
      case 'posted':
        if (!_isBoundedEmbeddedJson(event.data['post'])) {
          return InboxRefreshRequired(sequence: event.sequence);
        }
        final MattermostPostDto? raw = _postFromEvent(event.data);
        if (raw == null || raw.id.isEmpty) return null;
        if (raw.rootId.isNotEmpty) {
          if (raw.userId == session.userId || _isExcludedRealtimePost(raw)) {
            return null;
          }
          return _threadReplyFromEvent(session, event, raw);
        }
        if (raw.userId == session.userId) return null;
        if (_isExcludedRealtimePost(raw)) return null;
        if (!_hasRealtimeChannelScope(raw.channelId)) {
          // We cannot decide eligibility or construct a safe channel identity
          // locally. In particular, this must not become `candidate: null`,
          // which is a typed delete delta.
          return InboxRefreshRequired(sequence: event.sequence);
        }
        final InboxPostCandidate? created = await _mapRealtimePost(
          session,
          raw,
          serverMentions: _mentionsFromEvent(event.data),
          enforceEligibility: true,
        );
        return created == null
            ? null
            : InboxPostChanged(
                postId: raw.id,
                candidate: created,
                kind: InboxPostChangeKind.created,
                sequence: event.sequence,
                mentions: _stringList(event.data['mentions']),
                followers: _stringList(event.data['followers']),
                channelType: _optionalString(event.data['channel_type']),
              );
      case 'post_edited':
        if (!_isBoundedEmbeddedJson(event.data['post'])) {
          return InboxRefreshRequired(sequence: event.sequence);
        }
        final MattermostPostDto? raw = _postFromEvent(event.data);
        if (raw == null || raw.id.isEmpty || raw.rootId.isNotEmpty) return null;
        if (!_hasRealtimeChannelScope(raw.channelId)) {
          return InboxRefreshRequired(sequence: event.sequence);
        }
        final InboxPostCandidate? preview = await _mapRealtimePost(
          session,
          raw,
          enforceEligibility: false,
        );
        return preview == null
            ? null
            : InboxPostChanged(
                postId: raw.id,
                candidate: preview,
                kind: InboxPostChangeKind.edited,
                sequence: event.sequence,
                mentions: _stringList(event.data['mentions']),
                followers: _stringList(event.data['followers']),
                channelType: _optionalString(event.data['channel_type']),
              );
      case 'post_deleted':
        if (!_isBoundedEmbeddedJson(event.data['post'])) {
          return InboxRefreshRequired(sequence: event.sequence);
        }
        final MattermostPostDto? raw = _postFromEvent(event.data);
        final String postId =
            raw?.id ?? _optionalString(event.data['post_id']) ?? '';
        return postId.isEmpty
            ? null
            : InboxPostChanged(
                postId: postId,
                candidate: null,
                kind: InboxPostChangeKind.deleted,
                sequence: event.sequence,
              );
      case 'thread_updated':
        return _threadUpdatedFromEvent(session, event);
      case 'thread_follow_changed':
        return _threadFollowChangedFromEvent(session, event);
      case 'thread_read_changed':
        return _threadReadChangedFromEvent(event);
      case 'channel_member_updated':
        return _channelMembershipChangedFromEvent(session, event);
      case 'direct_added':
      case 'group_added':
        return _directOrGroupAddedFromEvent(event);
      case 'user_updated':
        return _currentUserChangedFromEvent(session, event);
      case 'preference_changed':
      case 'preferences_changed':
      case 'preferences_deleted':
        final List<InboxPreferenceChange> changes = _preferenceChanges(
          event.data,
        );
        if (changes.isEmpty) return null;
        return _preferenceEvent(event: event, changes: changes);
      default:
        return null;
    }
  }

  InboxRealtimeEvent? _channelMembershipChangedFromEvent(
    AuthSession session,
    MattermostWebSocketEvent event,
  ) {
    final Map<String, Object?> member = _eventMap(
      event.data['channel_member'] ?? event.data['member'],
    );
    final String? userId =
        _optionalString(member['user_id']) ??
        _optionalString(event.data['user_id']);
    final String? channelId =
        _optionalString(member['channel_id']) ??
        _optionalString(event.data['channel_id']) ??
        _optionalString(event.broadcast['channel_id']);
    if (userId != session.userId || channelId == null) return null;
    return InboxEligibilityContextChanged(
      sequence: event.sequence,
      kind: InboxEligibilityContextChangeKind.channelMembership,
    );
  }

  InboxRealtimeEvent? _directOrGroupAddedFromEvent(
    MattermostWebSocketEvent event,
  ) {
    final String? channelId =
        _optionalString(event.data['channel_id']) ??
        _optionalString(event.broadcast['channel_id']);
    if (channelId == null) return null;
    return InboxEligibilityContextChanged(
      sequence: event.sequence,
      kind: InboxEligibilityContextChangeKind.directOrGroupAdded,
    );
  }

  InboxRealtimeEvent? _currentUserChangedFromEvent(
    AuthSession session,
    MattermostWebSocketEvent event,
  ) {
    final Map<String, Object?> user = _eventMap(event.data['user']);
    final String? userId =
        _optionalString(user['id']) ?? _optionalString(event.data['user_id']);
    if (userId != session.userId) return null;
    return InboxEligibilityContextChanged(
      sequence: event.sequence,
      kind: InboxEligibilityContextChangeKind.currentUser,
    );
  }

  InboxRealtimeEvent? _preferenceEvent({
    required MattermostWebSocketEvent event,
    required List<InboxPreferenceChange> changes,
  }) {
    final bool deletion = event.name == 'preferences_deleted';
    final bool affectsDesktop = changes.any(
      (InboxPreferenceChange change) =>
          change.category == 'notifications' &&
          (change.name == 'desktop' || change.name == 'desktop_threads') &&
          (deletion || _isKnownDesktopPreferenceValue(change.value)),
    );
    if (affectsDesktop) {
      return InboxEligibilityContextChanged(
        sequence: event.sequence,
        kind: InboxEligibilityContextChangeKind.desktopNotifications,
      );
    }
    final List<InboxPreferenceChange> postponed = changes
        .where(
          (InboxPreferenceChange change) =>
              change.category == _postponedPreferenceCategory &&
              (deletion || _isValidPostponedPreference(change)),
        )
        .toList(growable: false);
    if (postponed.isEmpty) return null;
    return InboxRefreshRequired(
      sequence: event.sequence,
      scope: InboxRefreshScope.postponed,
    );
  }

  static bool _isKnownDesktopPreferenceValue(String? value) => switch (value) {
    'all' || 'mention' || 'none' || 'default' => true,
    _ => false,
  };

  static bool _isValidPostponedPreference(InboxPreferenceChange change) {
    final Object? decoded = _decodedJson(change.value);
    if (decoded is! Map<Object?, Object?>) return false;
    final Object? postId = decoded['post_id'];
    final Object? kind = decoded['kind'];
    final int? addedAt = _optionalInt(decoded['added_at']);
    return postId is String &&
        postId == change.name &&
        (kind == 'post' || kind == 'thread') &&
        addedAt != null &&
        addedAt >= 0;
  }

  Future<InboxThreadUpdated?> _threadUpdatedFromEvent(
    AuthSession session,
    MattermostWebSocketEvent event,
  ) async {
    final Map<String, Object?> thread = _eventMap(
      event.data['thread'] ?? event.data['user_thread'],
    );
    final String rootPostId =
        _optionalString(thread['id']) ??
        _optionalString(thread['thread_id']) ??
        _optionalString(thread['root_id']) ??
        _optionalString(event.data['thread_id']) ??
        _optionalString(event.data['root_id']) ??
        '';
    if (rootPostId.isEmpty) return null;
    final String? channelId =
        _optionalString(thread['channel_id']) ??
        _optionalString(event.data['channel_id']);
    final bool? isFollowing =
        _optionalBool(thread['is_following']) ??
        _optionalBool(event.data['is_following']);
    final int? unreadReplies = _optionalInt(thread['unread_replies']);
    final int? unreadMentions = _optionalInt(thread['unread_mentions']);
    if (isFollowing == false) {
      return InboxThreadUpdated(
        sequence: event.sequence,
        rootPostId: rootPostId,
        channelId: channelId,
        unreadReplies: unreadReplies,
        unreadMentions: unreadMentions,
        isFollowing: false,
        isInboxEligible: false,
      );
    }
    final bool? isEligible = _threadEligibility(
      channelId: channelId,
      unreadReplies: unreadReplies,
      unreadMentions: unreadMentions,
    );
    final InboxThreadCandidate? candidate = isEligible == true
        ? await _hydrateRealtimeThread(
            session: session,
            rootPostId: rootPostId,
            channelId: channelId,
          )
        : null;
    return InboxThreadUpdated(
      sequence: event.sequence,
      rootPostId: rootPostId,
      channelId: channelId,
      unreadReplies: unreadReplies,
      unreadMentions: unreadMentions,
      isFollowing: isFollowing,
      isInboxEligible: isEligible,
      candidate: candidate,
      recoveryRequired:
          isEligible == null || (isEligible == true && candidate == null),
    );
  }

  Future<InboxThreadFollowChanged?> _threadFollowChangedFromEvent(
    AuthSession session,
    MattermostWebSocketEvent event,
  ) async {
    final String rootPostId =
        _optionalString(event.data['thread_id']) ??
        _optionalString(event.data['root_id']) ??
        _optionalString(event.data['post_id']) ??
        '';
    if (rootPostId.isEmpty) return null;
    final bool? isFollowing =
        _optionalBool(event.data['is_following']) ??
        _optionalBool(event.data['following']);
    if (isFollowing == false) {
      return InboxThreadFollowChanged(
        sequence: event.sequence,
        rootPostId: rootPostId,
        isFollowing: false,
      );
    }
    final String? channelId = _optionalString(event.data['channel_id']);
    final InboxThreadCandidate? candidate = isFollowing == true
        ? await _hydrateRealtimeThread(
            session: session,
            rootPostId: rootPostId,
            channelId: channelId,
          )
        : null;
    return InboxThreadFollowChanged(
      sequence: event.sequence,
      rootPostId: rootPostId,
      isFollowing: isFollowing,
      candidate: candidate,
      recoveryRequired: isFollowing != false && candidate == null,
    );
  }

  Future<InboxThreadUpdated?> _threadReplyFromEvent(
    AuthSession session,
    MattermostWebSocketEvent event,
    MattermostPostDto reply,
  ) async {
    final InboxThreadCandidate? hydrated = await _hydrateRealtimeThread(
      session: session,
      rootPostId: reply.rootId,
      channelId: reply.channelId,
    );
    final _InboxRealtimeScope? scope = _realtimeScope;
    final List<String>? mentions = _mentionsFromEvent(event.data);
    final bool explicitMention =
        mentions?.any(
          (String mention) =>
              mention == session.userId ||
              mention == scope?.currentUser.username,
        ) ??
        false;
    final InboxThreadCandidate? candidate = hydrated == null
        ? null
        : InboxThreadCandidate(
            thread: hydrated.thread,
            channel: hydrated.channel,
            teamId: hydrated.teamId,
            rootAttentionReason: hydrated.rootAttentionReason,
            hasNewExplicitMention: explicitMention,
          );
    return InboxThreadUpdated(
      sequence: event.sequence,
      rootPostId: reply.rootId,
      channelId: reply.channelId,
      candidate: candidate,
      recoveryRequired: candidate == null,
    );
  }

  /// Hydrates only the CRT aggregate implicated by one known websocket event.
  /// It never falls back to guessed root or channel content.
  Future<InboxThreadCandidate?> _hydrateRealtimeThread({
    required AuthSession session,
    required String rootPostId,
    required String? channelId,
  }) async {
    final _InboxRealtimeScope? scope = _realtimeScope;
    final SidebarChannel? channel = channelId == null
        ? null
        : scope?.channels[channelId];
    final MattermostChannelMemberDto? member = channelId == null
        ? null
        : scope?.members[channelId];
    if (scope == null || channel == null || member == null) return null;
    try {
      final MattermostUserThreadDto? raw = await _api.getUserThread(
        userId: session.userId,
        teamId: channel.teamId,
        threadId: rootPostId,
      );
      if (raw == null ||
          raw.id != rootPostId ||
          raw.deleteAt != 0 ||
          raw.post == null ||
          raw.post!.deleteAt != 0 ||
          raw.post!.channelId != channel.id ||
          !_isRealtimeThreadEligible(raw, scope)) {
        return null;
      }
      final ChannelPost? root = await _mapRealtimeThreadRoot(
        session: session,
        raw: raw.post!,
        scope: scope,
      );
      if (root == null) return null;
      final InboxAttentionReason? rootReason = channel.isDialog
          ? InboxAttentionReason.allMessagesSubscription
          : _classifyRealtime(
              session: session,
              post: raw.post!,
              channel: channel,
              user: scope.currentUser,
              member: member,
              serverMentions: null,
            );
      return InboxThreadCandidate(
        channel: channel,
        teamId: channel.teamId,
        rootAttentionReason: rootReason,
        thread: FollowedThread(
          root: root.withThreadSummary(
            replyCount: raw.replyCount,
            lastReplyAt: raw.lastReplyAt == 0
                ? null
                : DateTime.fromMillisecondsSinceEpoch(raw.lastReplyAt),
          ),
          replyCount: raw.replyCount,
          lastReplyAt: raw.lastReplyAt == 0
              ? root.sentAt
              : DateTime.fromMillisecondsSinceEpoch(raw.lastReplyAt),
          lastViewedAt: DateTime.fromMillisecondsSinceEpoch(raw.lastViewedAt),
          unreadReplies: raw.unreadReplies,
          unreadMentions: raw.unreadMentions,
          participants: raw.participants
              .map(mapUserSummary)
              .map(
                (UserSummary user) => PostAuthor(
                  id: user.id,
                  displayName: user.fullName,
                  profileImageUpdatedAt: user.profileImageUpdatedAt,
                ),
              )
              .toList(growable: false),
        ),
      );
    } on RequestCancelledException {
      rethrow;
    } on Object {
      return null;
    }
  }

  Future<ChannelPost?> _mapRealtimeThreadRoot({
    required AuthSession session,
    required MattermostPostDto raw,
    required _InboxRealtimeScope scope,
  }) async {
    UserSummary? author = scope.authors[raw.userId];
    if (author == null && raw.userId.isNotEmpty) {
      final List<MattermostUserDto> users = await _api.getUsersByIds(<String>[
        raw.userId,
      ]);
      if (users.isNotEmpty) {
        final MattermostUserDto user = users.first;
        author = mapUserSummary(user);
        scope.authors[user.id] = author;
        _rawUsersAreBots[user.id] = user.isBot;
      }
    }
    final List<ChannelPost> mapped = _messageMapper.map(
      posts: <MattermostPostDto>[raw],
      users: author == null ? const <UserSummary>[] : <UserSummary>[author],
      currentUserId: session.userId,
      includeDeleted: true,
    );
    return mapped.isEmpty ? null : mapped.single;
  }

  bool? _threadEligibility({
    required String? channelId,
    required int? unreadReplies,
    required int? unreadMentions,
  }) {
    final _InboxRealtimeScope? scope = _realtimeScope;
    if (scope == null ||
        channelId == null ||
        unreadReplies == null ||
        unreadMentions == null) {
      return null;
    }
    final MattermostChannelMemberDto? member = scope.members[channelId];
    if (member == null) return null;
    return isFollowedThreadInboxEligible(
      channel: _channelNotificationSettings(member),
      user: _userNotificationSettings(scope.currentUser),
      unreadReplies: unreadReplies,
      unreadMentions: unreadMentions,
    );
  }

  bool _isRealtimeThreadEligible(
    MattermostUserThreadDto thread,
    _InboxRealtimeScope scope,
  ) {
    final MattermostPostDto? root = thread.post;
    final MattermostChannelMemberDto? member = root == null
        ? null
        : scope.members[root.channelId];
    return root != null &&
        member != null &&
        isFollowedThreadInboxEligible(
          channel: _channelNotificationSettings(member),
          user: _userNotificationSettings(scope.currentUser),
          unreadReplies: thread.unreadReplies,
          unreadMentions: thread.unreadMentions,
        );
  }

  InboxThreadReadChanged? _threadReadChangedFromEvent(
    MattermostWebSocketEvent event,
  ) {
    final String rootPostId =
        _optionalString(event.data['thread_id']) ??
        _optionalString(event.data['root_id']) ??
        _optionalString(event.data['post_id']) ??
        '';
    return rootPostId.isEmpty
        ? null
        : InboxThreadReadChanged(
            sequence: event.sequence,
            rootPostId: rootPostId,
          );
  }

  Future<InboxPostCandidate?> _mapRealtimePost(
    AuthSession session,
    MattermostPostDto raw, {
    List<String>? serverMentions,
    required bool enforceEligibility,
  }) async {
    final _InboxRealtimeScope? scope = _realtimeScope;
    final SidebarChannel? channel = scope?.channels[raw.channelId];
    final MattermostChannelMemberDto? member = scope?.members[raw.channelId];
    if (scope == null || channel == null || member == null) return null;

    UserSummary? author = scope.authors[raw.userId];
    if (author == null && raw.userId.isNotEmpty) {
      final List<MattermostUserDto> users = await _api.getUsersByIds(<String>[
        raw.userId,
      ]);
      if (users.isNotEmpty) {
        final MattermostUserDto user = users.first;
        author = mapUserSummary(user);
        scope.authors[user.id] = author;
        _rawUsersAreBots[user.id] = user.isBot;
      }
    }
    final List<ChannelPost> mapped = _messageMapper.map(
      posts: <MattermostPostDto>[raw],
      users: author == null ? const <UserSummary>[] : <UserSummary>[author],
      currentUserId: session.userId,
      includeDeleted: true,
    );
    if (mapped.isEmpty) return null;
    final InboxAttentionReason? reason = enforceEligibility
        ? _classifyRealtime(
            session: session,
            post: raw,
            channel: channel,
            user: scope.currentUser,
            member: member,
            serverMentions: serverMentions,
          )
        // The domain edit reducer intentionally retains the existing reason.
        // This placeholder value is never allowed to decide membership.
        : InboxAttentionReason.allMessagesSubscription;
    if (reason == null) return null;
    return InboxPostCandidate(
      post: mapped.single,
      channel: channel,
      reason: reason,
      isSystem: raw.type.startsWith('system_'),
      isSilentNotification: _isTrue(raw.props?.values['silent_notification']),
      isFromBot: _rawUsersAreBots[raw.userId] == true,
      isFromWebhook:
          _isTrue(raw.props?.values['from_bot']) ||
          _isTrue(raw.props?.values['from_webhook']),
      isFromPlugin: _isTrue(raw.props?.values['from_plugin']),
    );
  }

  InboxAttentionReason? _classifyRealtime({
    required AuthSession session,
    required MattermostPostDto post,
    required SidebarChannel channel,
    required MattermostUserDto user,
    required MattermostChannelMemberDto member,
    required List<String>? serverMentions,
  }) {
    final InboxDesktopNotificationLevel desktop =
        resolveInboxDesktopNotificationLevel(
          channel: _channelNotificationSettings(member).desktop,
          user: _userNotificationSettings(user).desktop,
        );
    if (desktop == InboxDesktopNotificationLevel.none) return null;
    if (channel.isDialog) return InboxAttentionReason.allMessagesSubscription;

    final bool exactServerMention =
        serverMentions?.any(
          (String value) => value == session.userId || value == user.username,
        ) ??
        false;
    if (exactServerMention) return InboxAttentionReason.directMention;

    final InboxChannelNotificationSettings channelSettings =
        _channelNotificationSettings(member);
    final InboxUserNotificationSettings userSettings =
        _userNotificationSettings(user);
    if (serverMentions != null) {
      // When the server gave an authoritative recipient list, textual @name
      // matches are merely display text. Do not turn them into an Inbox reason.
      return resolvesToAllMessagesSubscription(
            channel: channelSettings,
            user: userSettings,
          )
          ? InboxAttentionReason.allMessagesSubscription
          : null;
    }
    return classifyInboxAttention(
      message: post.message,
      username: user.username,
      firstName: user.firstName,
      mentionKeys: user.notifyProps?.mentionKeys ?? '',
      firstNameEnabled: _isEnabled(user.notifyProps?.firstName),
      channelMentionsEnabled: _isEnabled(user.notifyProps?.channel),
      ignoreChannelMentions: _isEnabled(
        member.notifyProps?.ignoreChannelMentions,
      ),
      allMessagesSubscription: resolvesToAllMessagesSubscription(
        channel: channelSettings,
        user: userSettings,
      ),
    );
  }

  bool _hasRealtimeChannelScope(String channelId) {
    final _InboxRealtimeScope? scope = _realtimeScope;
    return scope != null &&
        scope.channels.containsKey(channelId) &&
        scope.members.containsKey(channelId);
  }

  bool _isExcludedRealtimePost(MattermostPostDto raw) =>
      raw.type.startsWith('system_') ||
      raw.deleteAt != 0 ||
      _isTrue(raw.props?.values['silent_notification']);

  MattermostPostDto? _postFromEvent(Map<String, Object?> data) {
    final Object? rawPost = data['post'];
    final Object? decoded;
    try {
      decoded = rawPost is String ? jsonDecode(rawPost) : rawPost;
    } on FormatException {
      return null;
    }
    if (decoded is! Map<Object?, Object?>) return null;
    return MattermostPostDto.fromJson(
      decoded.map(
        (Object? key, Object? value) => MapEntry<String, Object?>(
          key is String ? key : key.toString(),
          value,
        ),
      ),
    );
  }

  static String? _optionalString(Object? value) => switch (value) {
    final String value when value.isNotEmpty => value,
    _ => null,
  };

  static int? _optionalInt(Object? value) => switch (value) {
    final int value => value,
    final num value => value.toInt(),
    final String value => int.tryParse(value),
    _ => null,
  };

  static bool? _optionalBool(Object? value) => switch (value) {
    final bool value => value,
    'true' => true,
    'false' => false,
    _ => null,
  };

  static Object? _decodedJson(Object? value) {
    if (value is! String) return value;
    if (value.length > _maxEmbeddedRealtimeJsonCharacters) return null;
    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }

  static bool _isBoundedEmbeddedJson(Object? value) =>
      value is! String || value.length <= _maxEmbeddedRealtimeJsonCharacters;

  static Map<String, Object?> _eventMap(Object? value) {
    final Object? decoded = _decodedJson(value);
    if (decoded is! Map<Object?, Object?>) return const <String, Object?>{};
    return decoded.map(
      (Object? key, Object? item) =>
          MapEntry<String, Object?>(key is String ? key : key.toString(), item),
    );
  }

  static List<String> _stringList(Object? value) {
    final Object? decoded = _decodedJson(value);
    if (decoded is! Iterable<Object?>) return const <String>[];
    return decoded
        .whereType<String>()
        .where((String id) => id.isNotEmpty)
        .toList(growable: false);
  }

  static List<String>? _mentionsFromEvent(Map<String, Object?> data) =>
      data.containsKey('mentions') ? _stringList(data['mentions']) : null;

  static bool _isEnabled(String? value) => value == 'true' || value == 'on';

  static List<InboxPreferenceChange> _preferenceChanges(
    Map<String, Object?> data,
  ) {
    final Object? raw = _decodedJson(data['preferences'] ?? data['preference']);
    final Iterable<Object?> records = switch (raw) {
      final Iterable<Object?> values => values,
      final Map<Object?, Object?> value => <Object?>[value],
      _ => <Object?>[data],
    };
    final List<InboxPreferenceChange> changes = <InboxPreferenceChange>[];
    for (final Object? record in records) {
      final Map<String, Object?> preference = _eventMap(record);
      final String? category = _optionalString(preference['category']);
      final String? name = _optionalString(preference['name']);
      if (category == null || name == null) continue;
      changes.add(
        InboxPreferenceChange(
          category: category,
          name: name,
          value: _optionalString(preference['value']),
        ),
      );
    }
    return List<InboxPreferenceChange>.unmodifiable(changes);
  }

  // Captures bot flags alongside the mapper's deliberately bot-neutral summary.
  final Map<String, bool> _rawUsersAreBots = <String, bool>{};

  InboxUserNotificationSettings _userNotificationSettings(
    MattermostUserDto user,
  ) {
    final UserNotifyPropsDto notify =
        user.notifyProps ?? const UserNotifyPropsDto();
    return InboxUserNotificationSettings(
      desktop: _desktopNotificationLevel(notify.desktop),
      desktopThreads: _desktopNotificationLevel(notify.desktopThreads),
    );
  }

  InboxChannelNotificationSettings _channelNotificationSettings(
    MattermostChannelMemberDto member,
  ) {
    final MattermostChannelNotifyPropsDto notify =
        member.notifyProps ?? const MattermostChannelNotifyPropsDto();
    return InboxChannelNotificationSettings(
      desktop: _desktopNotificationLevel(notify.desktop),
      markUnread: _markUnread(notify.markUnread),
    );
  }

  InboxDesktopNotificationLevel _desktopNotificationLevel(String value) =>
      switch (value) {
        'all' => InboxDesktopNotificationLevel.all,
        'mention' => InboxDesktopNotificationLevel.mention,
        'none' => InboxDesktopNotificationLevel.none,
        'default' || '' => InboxDesktopNotificationLevel.inherit,
        _ => InboxDesktopNotificationLevel.unknown,
      };

  InboxMarkUnread _markUnread(String value) => switch (value) {
    'all' => InboxMarkUnread.all,
    'mention' => InboxMarkUnread.mention,
    _ => InboxMarkUnread.unknown,
  };

  @override
  Future<void> markRead({
    required AuthSession session,
    required InboxItem item,
  }) => switch (item) {
    ThreadInboxItem(:final thread, :final teamId) => _api.updateThreadRead(
      userId: session.userId,
      teamId: teamId,
      threadId: thread.id,
      timestamp: _now().millisecondsSinceEpoch,
    ),
    ChannelPostInboxItem(:final post) => _api.viewChannel(
      userId: session.userId,
      channelId: post.channelId,
    ),
    DirectMessageBundleInboxItem(:final channelId) => _api.viewChannel(
      userId: session.userId,
      channelId: channelId,
    ),
    UnavailablePostponedInboxItem() => Future<void>.value(),
  };

  static bool _isTrue(JsonValueDto? value) => switch (value) {
    JsonBooleanDto(:final value) => value,
    JsonStringDto(:final value) => value == 'true',
    _ => false,
  };
}

final class _InboxRealtimeScope {
  _InboxRealtimeScope({
    required this.currentUser,
    required this.channels,
    required this.members,
    required this.authors,
  });

  final MattermostUserDto currentUser;
  final Map<String, SidebarChannel> channels;
  final Map<String, MattermostChannelMemberDto> members;
  final Map<String, UserSummary> authors;
}

/// Converts session transport signals into Inbox domain events without losing
/// the interval before the REST context establishes a channel scope.
final class _InboxRealtimeWatch {
  _InboxRealtimeWatch({
    required Stream<SessionRealtimeSignal> signals,
    required bool Function() isScopeReady,
    required InboxConnectionStatus Function(WebSocketConnectionStatus)
    mapConnectionStatus,
    required Future<InboxRealtimeEvent?> Function(MattermostWebSocketEvent)
    mapEvent,
    required void Function() onClosed,
  }) : _signals = signals,
       _isScopeReady = isScopeReady,
       _mapConnectionStatus = mapConnectionStatus,
       _mapEvent = mapEvent,
       _onClosed = onClosed;

  static const int _maxBufferedEvents = 128;

  final Stream<SessionRealtimeSignal> _signals;
  final bool Function() _isScopeReady;
  final InboxConnectionStatus Function(WebSocketConnectionStatus)
  _mapConnectionStatus;
  final Future<InboxRealtimeEvent?> Function(MattermostWebSocketEvent)
  _mapEvent;
  final void Function() _onClosed;
  final List<SessionRealtimeEventReceived> _scopeBuffer =
      <SessionRealtimeEventReceived>[];
  Future<void> _mappingTail = Future<void>.value();
  StreamSubscription<SessionRealtimeSignal>? _subscription;
  late final StreamController<InboxRealtimeEvent> _controller;
  bool _scopeBufferOverflowed = false;
  bool _closed = false;

  Stream<InboxRealtimeEvent> get stream {
    _controller = StreamController<InboxRealtimeEvent>(
      onListen: () {
        _subscription = _signals.listen(
          _onSignal,
          onError: (Object error, StackTrace stackTrace) {
            _enqueue(
              const SessionRealtimeConnectionChanged(
                WebSocketConnectionStatus.disconnected,
              ),
            );
          },
          onDone: _close,
        );
      },
      onCancel: _close,
    );
    return _controller.stream;
  }

  void _onSignal(SessionRealtimeSignal signal) {
    if (_closed) return;
    if (signal case SessionRealtimeEventReceived() when !_isScopeReady()) {
      if (_scopeBufferOverflowed) return;
      if (_scopeBuffer.length == _maxBufferedEvents) {
        _scopeBuffer.clear();
        _scopeBufferOverflowed = true;
        return;
      }
      _scopeBuffer.add(signal);
      return;
    }
    _enqueue(signal);
  }

  /// Called by the repository immediately after the REST context becomes
  /// available. The queue stays bounded and is mapped serially in `seq` order.
  void flushScopeBuffer() {
    if (_closed || !_isScopeReady()) return;
    if (_scopeBufferOverflowed) {
      _scopeBufferOverflowed = false;
      _scopeBuffer.clear();
      _enqueue(const SessionRealtimeRecoveryRequired());
      return;
    }
    _scopeBuffer.sort(
      (SessionRealtimeEventReceived left, SessionRealtimeEventReceived right) =>
          left.event.sequence.compareTo(right.event.sequence),
    );
    for (final SessionRealtimeEventReceived signal in _scopeBuffer) {
      _enqueue(signal);
    }
    _scopeBuffer.clear();
  }

  void _enqueue(SessionRealtimeSignal signal) {
    _mappingTail = _mappingTail.then((_) async {
      if (_closed) return;
      switch (signal) {
        case SessionRealtimeConnectionChanged(:final status):
          _add(InboxConnectionChanged(_mapConnectionStatus(status)));
        case SessionRealtimeRecoveryRequired():
          _add(const InboxRefreshRequired());
        case SessionRealtimeEventReceived(:final event):
          try {
            final InboxRealtimeEvent? mapped = await _mapEvent(event);
            if (mapped != null) _add(mapped);
          } on Object {
            // A malformed payload remains isolated to its event. Transport
            // sequence gaps and reconnects still request authoritative repair.
          }
      }
    });
  }

  void _add(InboxRealtimeEvent event) {
    if (!_closed && !_controller.isClosed) _controller.add(event);
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    _scopeBuffer.clear();
    await _subscription?.cancel();
    _onClosed();
    if (!_controller.isClosed) await _controller.close();
  }
}
