import 'dart:async';
import 'dart:convert';

import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/database/user_group_membership_cache.dart';
import 'package:mattermost_flutter/src/data/mappers/channel_sidebar_mapper.dart';
import 'package:mattermost_flutter/src/data/mappers/dialog_display_name_mapper.dart';
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
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/viewed_channel_posts.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/canonicalize_inbox_candidates.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/classify_inbox_attention.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/group_direct_messages.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/notification_eligibility.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/reconcile_queues.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/viewed_channel_posts_repository.dart';

/// Network-first Inbox snapshot builder and realtime event mapper.
///
/// Connection lifecycle stays in [WebSocketGateway], while this repository
/// maps transport events into the same domain candidates used by REST.
final class MattermostInboxRepository extends InboxRepository {
  MattermostInboxRepository({
    required MattermostApi api,
    required MessageMapper<MattermostPostDto, UserSummary> messageMapper,
    required PostponedRepository postponed,
    required UserGroupMembershipCache userGroupCache,
    ViewedChannelPostsRepository viewedChannelPosts =
        const _EmptyViewedChannelPostsRepository(),
    WebSocketGateway? webSocketGateway,
    CredentialStore? credentialStore,
    SessionRealtimeService? realtime,
    DateTime Function()? now,
  }) : _api = api,
       _messageMapper = messageMapper,
       _postponed = postponed,
       _viewedChannelPosts = viewedChannelPosts,
       _userGroupCache = userGroupCache,
       _realtime =
           realtime ??
           (webSocketGateway != null && credentialStore != null
               ? SessionRealtimeService(
                   gateway: webSocketGateway,
                   credentialStore: credentialStore,
                 )
               : null),
       _now = now ?? DateTime.now;

  static const int _authorBatchSize = 100;
  static const int _maxUnreadConcurrency = 4;
  static const Duration _groupMembershipTtl = Duration(days: 1);

  final MattermostApi _api;
  final MessageMapper<MattermostPostDto, UserSummary> _messageMapper;
  final PostponedRepository _postponed;
  final ViewedChannelPostsRepository _viewedChannelPosts;
  final UserGroupMembershipCache _userGroupCache;
  final SessionRealtimeService? _realtime;
  final DateTime Function() _now;
  final Set<String> _pendingViewedPreferenceCleanup = <String>{};
  _InboxRealtimeScope? _realtimeScope;

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
    'group_member_add',
    'group_member_delete',
  };

  @override
  Future<InboxSnapshot> load({required AuthSession session}) async {
    final DateTime builtAt = _now();
    await _retryViewedPreferenceCleanup(session);
    _rawUsersAreBots.clear();
    final Future<Set<String>> groupNamesRequest = _loadCurrentGroupNames(
      session: session,
      now: builtAt,
    );
    final MattermostUserDto currentUser = await _api.getCurrentUser();
    final Set<String> groupMentionNames = await groupNamesRequest;
    final List<MattermostTeamDto> teams = await _api.getTeamsForCurrentUser();
    final List<_TeamChannels> teamChannels = await Future.wait(
      teams.map(
        (MattermostTeamDto team) async => _TeamChannels(
          channels: await _api.getChannelsForUser(
            userId: session.userId,
            teamId: team.id,
          ),
          members: await _api.getChannelMembersForUser(
            userId: session.userId,
            teamId: team.id,
          ),
        ),
      ),
    );
    final PostponedReferencesSnapshot postponed = await _postponed.load(
      session: session,
    );
    final ViewedChannelPostsSnapshot viewedChannelPosts =
        await _viewedChannelPosts.load(session: session);
    final Map<String, MattermostChannelDto> channels =
        <String, MattermostChannelDto>{};
    final Map<String, MattermostChannelMemberDto> members =
        <String, MattermostChannelMemberDto>{};
    for (final _TeamChannels snapshot in teamChannels) {
      for (final MattermostChannelDto channel in snapshot.channels) {
        channels.putIfAbsent(channel.id, () => channel);
      }
      for (final MattermostChannelMemberDto member in snapshot.members) {
        members.putIfAbsent(member.channelId, () => member);
      }
    }
    await _cleanupReadChannelPreferences(
      session: session,
      viewedChannelPosts: viewedChannelPosts,
      channels: channels,
      members: members,
    );
    final Map<String, SidebarChannel> knownChannels =
        await _resolveKnownChannels(
          rawChannels: channels,
          currentUserId: session.userId,
        );

    final List<_TeamThreads> unreadThreadPages = await Future.wait(
      teams.map(
        (MattermostTeamDto team) async => _TeamThreads(
          team.id,
          await _loadUnreadThreads(userId: session.userId, teamId: team.id),
        ),
      ),
    );
    final Map<String, _ThreadSource> rawThreads = <String, _ThreadSource>{};
    for (final _TeamThreads page in unreadThreadPages) {
      for (final MattermostUserThreadDto thread in page.threads) {
        if (thread.post == null ||
            thread.deleteAt != 0 ||
            thread.unreadReplies <= 0) {
          continue;
        }
        rawThreads.putIfAbsent(
          thread.id,
          () => _ThreadSource(teamId: page.teamId, raw: thread),
        );
      }
    }

    final (
      List<_UnreadChannelPosts> unread,
      Map<String, List<MattermostPostDto>> unreadThreadPosts,
    ) = await (
      _loadUnreadPosts(
        channels: channels,
        members: members,
        currentUser: currentUser,
      ),
      _loadUnreadThreadPosts(rawThreads.values),
    ).wait;
    final Set<String> postponedIds = postponed.references
        .map((PostponedReference reference) => reference.postId)
        .toSet();
    final Map<String, MattermostPostDto> rawPosts = <String, MattermostPostDto>{
      for (final _UnreadChannelPosts entry in unread)
        for (final MattermostPostDto post in entry.posts) post.id: post,
      for (final _ThreadSource source in rawThreads.values)
        if (source.raw.post != null) source.raw.post!.id: source.raw.post!,
    };
    for (final List<String> batch in _batches(postponedIds.toList())) {
      final List<MattermostPostDto> hydrated = await _api.getPostsByIds(batch);
      for (final MattermostPostDto post in hydrated) {
        rawPosts[post.id] = post;
      }
    }
    final Map<String, UserSummary> authors = await _loadAuthors(
      rawPosts.values,
    );
    final Map<String, ChannelPost> mappedById = <String, ChannelPost>{
      for (final ChannelPost post in _messageMapper.map(
        posts: rawPosts.values,
        users: authors.values,
        currentUserId: session.userId,
        includeDeleted: true,
      ))
        post.id: post,
    };

    final List<InboxThreadCandidate> threadCandidates = rawThreads.values
        .map(
          (_ThreadSource source) => _mapThread(
            source,
            mappedById,
            knownChannels,
            members,
            currentUser,
            groupMentionNames,
            unreadThreadPosts[source.raw.id] ?? const <MattermostPostDto>[],
          ),
        )
        .whereType<InboxThreadCandidate>()
        .toList(growable: false);
    final List<InboxPostCandidate> newCandidates = <InboxPostCandidate>[];
    var incompleteMentions = false;
    for (final _UnreadChannelPosts entry in unread) {
      final SidebarChannel? channel = knownChannels[entry.channelId];
      final MattermostChannelMemberDto? member = members[entry.channelId];
      if (channel == null || member == null) continue;
      var reconstructedMentions = 0;
      for (final MattermostPostDto raw in entry.posts) {
        final ChannelPost? mapped = mappedById[raw.id];
        if (mapped == null || raw.userId == session.userId) continue;
        final InboxAttentionMatch? attention = channel.isDialog
            ? const InboxAttentionMatch(
                reason: InboxAttentionReason.allMessagesSubscription,
              )
            : _classify(
                raw,
                currentUser,
                member,
                groupMentionNames: groupMentionNames,
              );
        if (attention == null) continue;
        if (attention.reason != InboxAttentionReason.allMessagesSubscription) {
          reconstructedMentions++;
        }
        if (!channel.isDialog &&
            viewedChannelPosts.forChannel(channel.id).contains(raw.id)) {
          continue;
        }
        newCandidates.add(
          InboxPostCandidate(
            post: mapped,
            channel: channel,
            reason: attention.reason,
            groupMentionHandle: attention.groupMentionHandle,
            isSystem: raw.type.startsWith('system_'),
            isSilentNotification: _isTrue(
              raw.props?.values['silent_notification'],
            ),
            isFromBot:
                authors[raw.userId]?.id.isNotEmpty == true &&
                _rawUsersAreBots[raw.userId] == true,
            isFromWebhook: _isTrue(raw.props?.values['from_webhook']),
            isFromPlugin: _isTrue(raw.props?.values['from_plugin']),
          ),
        );
      }
      if (!channel.isDialog &&
          reconstructedMentions < member.mentionCountRoot) {
        incompleteMentions = true;
      }
    }

    final List<InboxItem> postponedItems = _postponedItems(
      references: postponed.references,
      rawPosts: rawPosts,
      mappedById: mappedById,
      channels: knownChannels,
      authors: authors,
      currentUser: currentUser,
      members: members,
      groupMentionNames: groupMentionNames,
    );
    // TODO(inbox): API v4 counters cannot identify all historical mentions;
    // @here still requires send-time presence from server delivery context.
    final List<InboxItem> newItems = groupDirectMessages(
      canonicalizeInboxCandidates(
        InboxSourceSnapshot(threads: threadCandidates, posts: newCandidates),
      ),
    );
    final InboxSnapshot result = reconcileQueues(
      newItems: newItems,
      postponedItems: postponedItems,
      builtAt: builtAt,
      hasIncompleteMentionReconstruction: incompleteMentions,
    );
    _realtimeScope = _InboxRealtimeScope(
      currentUser: currentUser,
      channels: knownChannels,
      members: Map<String, MattermostChannelMemberDto>.of(members),
      authors: Map<String, UserSummary>.of(authors),
      groupMentionNames: groupMentionNames,
      viewedPostIdsByChannelId: <String, Set<String>>{
        for (final MapEntry(:key, :value)
            in viewedChannelPosts.postIdsByChannelId.entries)
          key: Set<String>.of(value),
      },
    );
    return result;
  }

  @override
  Stream<InboxRealtimeEvent> watch({required AuthSession session}) {
    final SessionRealtimeService? realtime = _realtime;
    if (realtime == null) return const Stream<InboxRealtimeEvent>.empty();
    return realtime
        .watch(
          session: session,
          subscription: SessionRealtimeSubscription(
            eventNames: _realtimeEventNames,
            acceptsChannel: (String channelId) =>
                _realtimeScope?.channels.containsKey(channelId) == true,
          ),
        )
        .asyncMap((SessionRealtimeSignal signal) async {
          switch (signal) {
            case SessionRealtimeConnectionChanged(:final status):
              return <InboxRealtimeEvent>[
                InboxConnectionChanged(_mapConnectionStatus(status)),
              ];
            case SessionRealtimeRecoveryRequired():
              return const <InboxRealtimeEvent>[InboxRefreshRequired()];
            case SessionRealtimeEventReceived(:final event):
              try {
                final InboxRealtimeEvent? mapped = await _mapRealtimeEvent(
                  session,
                  event,
                );
                return mapped == null
                    ? const <InboxRealtimeEvent>[]
                    : <InboxRealtimeEvent>[mapped];
              } on Object {
                // Isolate malformed/unsupported events. Only reconnects and
                // sequence gaps require an authoritative reload.
                return const <InboxRealtimeEvent>[];
              }
          }
        })
        .expand((List<InboxRealtimeEvent> events) => events);
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
      case 'post_edited':
        final MattermostPostDto? raw = _postFromEvent(event.data);
        if (raw == null || raw.id.isEmpty) return null;
        // A matching thread_updated event carries the aggregate needed to
        // project replies. The reply itself must not trigger a REST reload.
        if (raw.rootId.isNotEmpty) return null;
        if (raw.userId == session.userId) return null;
        return InboxPostChanged(
          postId: raw.id,
          candidate: await _mapRealtimePost(
            session,
            raw,
            serverMentioned: _eventMentionsUser(event.data, session.userId),
          ),
        );
      case 'post_deleted':
        final MattermostPostDto? raw = _postFromEvent(event.data);
        final Object? idValue = event.data['post_id'];
        final String postId = raw?.id ?? (idValue is String ? idValue : '');
        return postId.isEmpty
            ? null
            : InboxPostChanged(postId: postId, candidate: null);
      case 'thread_updated':
      case 'thread_follow_changed':
      case 'thread_read_changed':
        // Thread websocket payloads do not contain the complete projection
        // needed by Inbox. Rebuild from the authoritative thread endpoint so
        // ordering and unread counters stay correct.
        return const InboxRefreshRequired();
      case 'preference_changed':
      case 'preferences_changed':
      case 'preferences_deleted':
        return null;
      case 'group_member_add':
      case 'group_member_delete':
        return _eventTargetsUser(event, session.userId)
            ? const InboxRefreshRequired()
            : null;
      default:
        return null;
    }
  }

  Future<InboxPostCandidate?> _mapRealtimePost(
    AuthSession session,
    MattermostPostDto raw, {
    required bool? serverMentioned,
  }) async {
    final _InboxRealtimeScope? scope = _realtimeScope;
    final SidebarChannel? channel = scope?.channels[raw.channelId];
    final MattermostChannelMemberDto? member = scope?.members[raw.channelId];
    if (scope == null || channel == null || member == null) return null;
    if (!channel.isDialog &&
        scope.viewedPostIdsByChannelId[raw.channelId]?.contains(raw.id) ==
            true) {
      return null;
    }
    if (raw.type.startsWith('system_') ||
        raw.deleteAt != 0 ||
        _isTrue(raw.props?.values['silent_notification'])) {
      return null;
    }

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
    final InboxAttentionMatch? attention = channel.isDialog
        ? const InboxAttentionMatch(
            reason: InboxAttentionReason.allMessagesSubscription,
          )
        : _classifyRealtime(
            raw,
            scope.currentUser,
            member,
            groupMentionNames: scope.groupMentionNames,
            serverMentioned: serverMentioned,
          );
    if (attention == null) return null;
    return InboxPostCandidate(
      post: mapped.single,
      channel: channel,
      reason: attention.reason,
      groupMentionHandle: attention.groupMentionHandle,
      isSystem: raw.type.startsWith('system_'),
      isSilentNotification: _isTrue(raw.props?.values['silent_notification']),
      isFromBot: _rawUsersAreBots[raw.userId] == true,
      isFromWebhook:
          _isTrue(raw.props?.values['from_bot']) ||
          _isTrue(raw.props?.values['from_webhook']),
      isFromPlugin: _isTrue(raw.props?.values['from_plugin']),
    );
  }

  InboxAttentionMatch? _classifyRealtime(
    MattermostPostDto post,
    MattermostUserDto user,
    MattermostChannelMemberDto member, {
    required Set<String> groupMentionNames,
    required bool? serverMentioned,
  }) {
    final MattermostChannelNotifyPropsDto notify =
        member.notifyProps ?? const MattermostChannelNotifyPropsDto();
    final UserNotifyPropsDto userNotify =
        user.notifyProps ?? const UserNotifyPropsDto();
    final bool allMessagesSubscription = resolvesToAllMessagesSubscription(
      memberMarkUnread: notify.markUnread,
      memberDesktop: notify.desktop,
      memberPush: notify.push,
      userDesktop: userNotify.desktop,
      userPush: userNotify.push,
    );
    final InboxAttentionMatch? reconstructed = classifyInboxAttentionMatch(
      message: post.message,
      username: user.username,
      firstName: user.firstName,
      mentionKeys: userNotify.mentionKeys,
      firstNameEnabled: userNotify.firstName == 'true',
      channelMentionsEnabled: userNotify.channel == 'true',
      ignoreChannelMentions: notify.ignoreChannelMentions == 'on',
      allMessagesSubscription: allMessagesSubscription,
      groupMentionNames: groupMentionNames,
    );
    if (serverMentioned == null) return reconstructed;
    if (!serverMentioned) {
      return allMessagesSubscription
          ? const InboxAttentionMatch(
              reason: InboxAttentionReason.allMessagesSubscription,
            )
          : null;
    }
    return reconstructed == null ||
            reconstructed.reason == InboxAttentionReason.allMessagesSubscription
        ? const InboxAttentionMatch(reason: InboxAttentionReason.directMention)
        : reconstructed;
  }

  bool? _eventMentionsUser(Map<String, Object?> data, String userId) {
    final Object? rawMentions = data['mentions'];
    if (rawMentions == null) return null;
    final Object? decoded;
    try {
      decoded = rawMentions is String ? jsonDecode(rawMentions) : rawMentions;
    } on FormatException {
      return null;
    }
    if (decoded is! List<Object?>) return null;
    return decoded.whereType<String>().contains(userId);
  }

  bool _eventTargetsUser(MattermostWebSocketEvent event, String userId) {
    final Object? broadcastUserId = event.broadcast['user_id'];
    if (broadcastUserId == userId) return true;
    final Object? rawMembership = event.data['group_member'];
    final Object? decoded;
    try {
      decoded = rawMembership is String
          ? jsonDecode(rawMembership)
          : rawMembership;
    } on FormatException {
      return false;
    }
    return decoded is Map<Object?, Object?> && decoded['user_id'] == userId;
  }

  Future<Set<String>> _loadCurrentGroupNames({
    required AuthSession session,
    required DateTime now,
  }) async {
    try {
      final List<MattermostGroupDto> groups = await _api.getGroupsForUser(
        session.userId,
      );
      final DateTime expiresAt = now.add(_groupMembershipTtl);
      final List<CachedUserGroup> cached = groups
          .where(_isUsableMentionGroup)
          .map(
            (MattermostGroupDto group) => CachedUserGroup(
              groupId: group.id,
              name: group.name,
              displayName: group.displayName,
              allowReference: group.allowReference,
              deleteAt: group.deleteAt,
              expiresAt: expiresAt,
            ),
          )
          .toList(growable: false);
      try {
        await _userGroupCache.replaceAll(
          accountId: session.durableDataScopeId,
          groups: cached,
        );
      } on Object {
        // A durable-cache failure must not discard the fresh server result.
      }
      return cached.map((CachedUserGroup group) => group.name).toSet();
    } on Object {
      try {
        final List<CachedUserGroup> cached = await _userGroupCache.getFresh(
          accountId: session.durableDataScopeId,
          now: now,
        );
        return cached
            .where(
              (CachedUserGroup group) =>
                  group.deleteAt == 0 &&
                  group.allowReference &&
                  group.name.trim().isNotEmpty,
            )
            .map((CachedUserGroup group) => group.name)
            .toSet();
      } on Object {
        return <String>{};
      }
    }
  }

  bool _isUsableMentionGroup(MattermostGroupDto group) =>
      group.id.isNotEmpty &&
      group.name.trim().isNotEmpty &&
      group.deleteAt == 0 &&
      group.allowReference;

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

  // Captures bot flags alongside the mapper's deliberately bot-neutral summary.
  final Map<String, bool> _rawUsersAreBots = <String, bool>{};

  Future<Map<String, UserSummary>> _loadAuthors(
    Iterable<MattermostPostDto> posts,
  ) async {
    final Set<String> ids = posts
        .map((MattermostPostDto post) => post.userId)
        .where((String id) => id.isNotEmpty)
        .toSet();
    final Map<String, UserSummary> result = <String, UserSummary>{};
    for (final List<String> batch in _batches(ids.toList())) {
      final List<MattermostUserDto> users = await _api.getUsersByIds(batch);
      for (final MattermostUserDto user in users) {
        result[user.id] = mapUserSummary(user);
        _rawUsersAreBots[user.id] = user.isBot;
      }
    }
    return result;
  }

  Future<List<MattermostUserThreadDto>> _loadUnreadThreads({
    required String userId,
    required String teamId,
  }) async {
    final List<MattermostUserThreadDto> result = <MattermostUserThreadDto>[];
    String? before;
    final Set<String> cursors = <String>{};
    while (true) {
      final MattermostUserThreadsDto page = await _api.getUserThreads(
        userId: userId,
        teamId: teamId,
        before: before,
        unread: true,
      );
      result.addAll(page.threads);
      if (page.threads.length < 60) return result;
      final String next = page.threads.last.id;
      if (!cursors.add(next)) return result;
      before = next;
    }
  }

  Future<Map<String, List<MattermostPostDto>>> _loadUnreadThreadPosts(
    Iterable<_ThreadSource> sources,
  ) async {
    final List<_ThreadSource> mentionedThreads = sources
        .where((_ThreadSource source) => source.raw.unreadMentions > 0)
        .toList(growable: false);
    final Map<String, List<MattermostPostDto>> result =
        <String, List<MattermostPostDto>>{};
    for (
      var start = 0;
      start < mentionedThreads.length;
      start += _maxUnreadConcurrency
    ) {
      final List<_ThreadSource> group = mentionedThreads.sublist(
        start,
        start + _maxUnreadConcurrency > mentionedThreads.length
            ? mentionedThreads.length
            : start + _maxUnreadConcurrency,
      );
      result.addEntries(
        await Future.wait(
          group.map((_ThreadSource source) async {
            final List<MattermostPostDto> posts =
                await _loadUnreadThreadPostsPage(source.raw);
            return MapEntry<String, List<MattermostPostDto>>(
              source.raw.id,
              posts,
            );
          }),
        ),
      );
    }
    return result;
  }

  Future<List<MattermostPostDto>> _loadUnreadThreadPostsPage(
    MattermostUserThreadDto thread,
  ) async {
    final Map<String, MattermostPostDto> posts = <String, MattermostPostDto>{};
    String? fromPost;
    int? fromCreateAt = thread.lastViewedAt;
    final Set<String> cursors = <String>{};
    while (true) {
      final MattermostPostListDto page = await _api.getPostThread(
        rootPostId: thread.id,
        fromPost: fromPost,
        fromCreateAt: fromCreateAt,
        direction: PostThreadDirection.down,
      );
      posts.addAll(page.posts);
      if (!page.hasNext) break;
      final String nextId = page.nextPostId.isNotEmpty
          ? page.nextPostId
          : page.order.lastOrNull ?? '';
      final MattermostPostDto? next = page.posts[nextId];
      if (next == null || !cursors.add(nextId)) {
        throw const FormatException(
          'Unread thread pagination cursor did not advance',
        );
      }
      fromPost = nextId;
      fromCreateAt = next.createAt;
    }
    return posts.values
        .where(
          (MattermostPostDto post) =>
              post.rootId == thread.id &&
              post.createAt > thread.lastViewedAt &&
              post.deleteAt == 0,
        )
        .toList(growable: false);
  }

  Future<List<_UnreadChannelPosts>> _loadUnreadPosts({
    required Map<String, MattermostChannelDto> channels,
    required Map<String, MattermostChannelMemberDto> members,
    required MattermostUserDto currentUser,
  }) async {
    final List<String> ids = channels.keys
        .where((String id) {
          final MattermostChannelDto channel = channels[id]!;
          final MattermostChannelMemberDto? member = members[id];
          if (member == null) return false;
          return _shouldLoadUnreadPosts(channel, member, currentUser);
        })
        .toList(growable: false);
    final List<_UnreadChannelPosts> result = <_UnreadChannelPosts>[];
    for (var start = 0; start < ids.length; start += _maxUnreadConcurrency) {
      final List<String> group = ids.sublist(
        start,
        start + _maxUnreadConcurrency > ids.length
            ? ids.length
            : start + _maxUnreadConcurrency,
      );
      result.addAll(
        await Future.wait(
          group.map((String channelId) async {
            final MattermostPostListDto response = await _api
                .getUnreadPostsForChannel(
                  userId: members[channelId]!.userId,
                  channelId: channelId,
                );
            final int viewedAt = members[channelId]!.lastViewedAt;
            return _UnreadChannelPosts(
              channelId,
              response.posts.values
                  .where((MattermostPostDto post) => post.createAt > viewedAt)
                  .toList(growable: false),
            );
          }),
        ),
      );
    }
    return result;
  }

  bool _shouldLoadUnreadPosts(
    MattermostChannelDto channel,
    MattermostChannelMemberDto member,
    MattermostUserDto currentUser,
  ) {
    final bool dialog = channel.type == 'D' || channel.type == 'G';
    if (dialog) return channel.totalMessageCount > member.msgCount;

    final bool hasUnreadRoots =
        channel.totalMessageCountRoot > member.msgCountRoot;
    if (!hasUnreadRoots) return false;
    if (member.mentionCountRoot > 0) return true;

    final MattermostChannelNotifyPropsDto notify =
        member.notifyProps ?? const MattermostChannelNotifyPropsDto();
    final UserNotifyPropsDto userNotify =
        currentUser.notifyProps ?? const UserNotifyPropsDto();
    return resolvesToAllMessagesSubscription(
      memberMarkUnread: notify.markUnread,
      memberDesktop: notify.desktop,
      memberPush: notify.push,
      userDesktop: userNotify.desktop,
      userPush: userNotify.push,
    );
  }

  InboxAttentionMatch? _classify(
    MattermostPostDto post,
    MattermostUserDto user,
    MattermostChannelMemberDto member, {
    required Set<String> groupMentionNames,
  }) => _classifyAll(
    post,
    user,
    member,
    groupMentionNames: groupMentionNames,
  ).firstOrNull;

  List<InboxAttentionMatch> _classifyAll(
    MattermostPostDto post,
    MattermostUserDto user,
    MattermostChannelMemberDto member, {
    required Set<String> groupMentionNames,
  }) {
    final MattermostChannelNotifyPropsDto notify =
        member.notifyProps ?? const MattermostChannelNotifyPropsDto();
    final UserNotifyPropsDto userNotify =
        user.notifyProps ?? const UserNotifyPropsDto();
    return classifyInboxAttentionMatches(
      message: post.message,
      username: user.username,
      firstName: user.firstName,
      mentionKeys: userNotify.mentionKeys,
      firstNameEnabled: userNotify.firstName == 'true',
      channelMentionsEnabled: userNotify.channel == 'true',
      ignoreChannelMentions: notify.ignoreChannelMentions == 'on',
      groupMentionNames: groupMentionNames,
      allMessagesSubscription: resolvesToAllMessagesSubscription(
        memberMarkUnread: notify.markUnread,
        memberDesktop: notify.desktop,
        memberPush: notify.push,
        userDesktop: userNotify.desktop,
        userPush: userNotify.push,
      ),
    );
  }

  InboxThreadCandidate? _mapThread(
    _ThreadSource source,
    Map<String, ChannelPost> mappedById,
    Map<String, SidebarChannel> channels,
    Map<String, MattermostChannelMemberDto> members,
    MattermostUserDto currentUser,
    Set<String> groupMentionNames,
    List<MattermostPostDto> unreadPosts,
  ) {
    final MattermostUserThreadDto raw = source.raw;
    final ChannelPost? root = raw.post == null
        ? null
        : mappedById[raw.post!.id];
    final SidebarChannel? channel = root == null
        ? null
        : channels[root.channelId];
    if (root == null || channel == null) return null;
    final MattermostChannelMemberDto? member = members[root.channelId];
    final InboxThreadMentionDetails? unreadMentionDetails =
        raw.unreadMentions == 0
        ? null
        : _threadMentionDetails(
            unreadPosts: unreadPosts,
            expectedCount: raw.unreadMentions,
            member: member,
            currentUser: currentUser,
            groupMentionNames: groupMentionNames,
          );
    final InboxAttentionMatch? rootAttention = channel.isDialog
        ? const InboxAttentionMatch(
            reason: InboxAttentionReason.allMessagesSubscription,
          )
        : member == null || raw.post == null
        ? null
        : _classify(
            raw.post!,
            currentUser,
            member,
            groupMentionNames: groupMentionNames,
          );
    return InboxThreadCandidate(
      channel: channel,
      teamId: source.teamId,
      rootAttentionReason: rootAttention?.reason,
      unreadMentionDetails: unreadMentionDetails,
      thread: FollowedThread(
        root: root.withThreadSummary(
          replyCount: raw.replyCount,
          lastReplyAt: raw.lastReplyAt == 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(raw.lastReplyAt),
        ),
        replyCount: raw.replyCount,
        lastReplyAt: DateTime.fromMillisecondsSinceEpoch(raw.lastReplyAt),
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
  }

  InboxThreadMentionDetails _threadMentionDetails({
    required List<MattermostPostDto> unreadPosts,
    required int expectedCount,
    required MattermostChannelMemberDto? member,
    required MattermostUserDto currentUser,
    required Set<String> groupMentionNames,
  }) {
    var mentionsCurrentUser = false;
    var mentionsChannel = false;
    var classifiedCount = 0;
    final Set<String> groupMentionHandles = <String>{};
    if (member != null) {
      for (final MattermostPostDto post in unreadPosts) {
        if (post.userId == currentUser.id ||
            post.type.startsWith('system_') ||
            _isTrue(post.props?.values['silent_notification'])) {
          continue;
        }
        final List<InboxAttentionMatch> matches =
            _classifyAll(
                  post,
                  currentUser,
                  member,
                  groupMentionNames: groupMentionNames,
                )
                .where((InboxAttentionMatch match) {
                  return match.reason !=
                      InboxAttentionReason.allMessagesSubscription;
                })
                .toList(growable: false);
        if (matches.isEmpty) continue;
        classifiedCount++;
        for (final InboxAttentionMatch match in matches) {
          switch (match.reason) {
            case InboxAttentionReason.directMention ||
                InboxAttentionReason.keywordMention:
              mentionsCurrentUser = true;
            case InboxAttentionReason.groupMention:
              final String? handle = match.groupMentionHandle;
              if (handle != null && handle.trim().isNotEmpty) {
                groupMentionHandles.add(handle);
              }
            case InboxAttentionReason.channelMention:
              mentionsChannel = true;
            case InboxAttentionReason.allMessagesSubscription:
              break;
          }
        }
      }
    }
    return InboxThreadMentionDetails(
      mentionsCurrentUser: mentionsCurrentUser,
      mentionsChannel: mentionsChannel,
      groupMentionHandles: groupMentionHandles,
      unclassifiedCount: expectedCount > classifiedCount
          ? expectedCount - classifiedCount
          : 0,
    );
  }

  List<InboxItem> _postponedItems({
    required List<PostponedReference> references,
    required Map<String, MattermostPostDto> rawPosts,
    required Map<String, ChannelPost> mappedById,
    required Map<String, SidebarChannel> channels,
    required Map<String, UserSummary> authors,
    required MattermostUserDto currentUser,
    required Map<String, MattermostChannelMemberDto> members,
    required Set<String> groupMentionNames,
  }) {
    final List<InboxPostCandidate> posts = <InboxPostCandidate>[];
    final List<InboxItem> threads = <InboxItem>[];
    for (final PostponedReference reference in references) {
      final MattermostPostDto? raw = rawPosts[reference.postId];
      final ChannelPost? post = mappedById[reference.postId];
      final SidebarChannel? channel = raw == null
          ? null
          : channels[raw.channelId];
      if (raw == null || post == null || channel == null) {
        // TODO(inbox): Domain has no unavailable-post placeholder yet; retain
        // the preference remotely and surface it when a placeholder is added.
        continue;
      }
      if (reference.kind == PostponedReferenceKind.thread) {
        threads.add(
          ThreadInboxItem(
            channel: channel,
            teamId: channel.teamId,
            thread: FollowedThread(
              root: post,
              replyCount: post.replyCount,
              lastReplyAt: post.lastReplyAt ?? post.sentAt,
              lastViewedAt: post.sentAt,
              unreadReplies: 0,
              unreadMentions: 0,
            ),
            postponedAt: reference.addedAt,
          ),
        );
      } else {
        final MattermostChannelMemberDto? member = members[raw.channelId];
        final InboxAttentionMatch? attention = channel.isDialog
            ? const InboxAttentionMatch(
                reason: InboxAttentionReason.allMessagesSubscription,
              )
            : member == null
            ? null
            : _classify(
                raw,
                currentUser,
                member,
                groupMentionNames: groupMentionNames,
              );
        posts.add(
          InboxPostCandidate(
            post: post,
            channel: channel,
            reason:
                attention?.reason ??
                InboxAttentionReason.allMessagesSubscription,
            groupMentionHandle: attention?.groupMentionHandle,
            isFromBot: _rawUsersAreBots[raw.userId] == true,
            isFromWebhook: _isTrue(raw.props?.values['from_webhook']),
            isFromPlugin: _isTrue(raw.props?.values['from_plugin']),
          ),
        );
      }
    }
    final List<InboxItem> grouped = groupDirectMessages(
      canonicalizeInboxCandidates(InboxSourceSnapshot(posts: posts)),
    ).map((InboxItem item) => _withPostponedAt(item, references)).toList();
    return <InboxItem>[...threads, ...grouped];
  }

  InboxItem _withPostponedAt(InboxItem item, List<PostponedReference> refs) {
    final DateTime addedAt = refs
        .where((PostponedReference ref) => item.postIds.contains(ref.postId))
        .map((PostponedReference ref) => ref.addedAt)
        .reduce((DateTime a, DateTime b) => a.isAfter(b) ? a : b);
    return switch (item) {
      ChannelPostInboxItem() => ChannelPostInboxItem(
        candidate: item.candidate,
        postponedAt: addedAt,
      ),
      DirectMessageBundleInboxItem() => DirectMessageBundleInboxItem(
        channelId: item.channelId,
        authorId: item.authorId,
        automationClass: item.automationClass,
        messages: item.messages,
        postponedAt: addedAt,
      ),
      ThreadInboxItem() => item,
    };
  }

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
    ChannelPostInboxItem(:final post) => _markChannelRead(
      session: session,
      channelId: post.channelId,
    ),
    DirectMessageBundleInboxItem(:final channelId) => _api.viewChannel(
      userId: session.userId,
      channelId: channelId,
    ),
  };

  @override
  Future<void> markPostViewed({
    required AuthSession session,
    required ChannelPostInboxItem item,
  }) async {
    await _viewedChannelPosts.add(
      session: session,
      channelId: item.post.channelId,
      postId: item.post.id,
    );
    _realtimeScope?.viewedPostIdsByChannelId
        .putIfAbsent(item.post.channelId, () => <String>{})
        .add(item.post.id);
  }

  Future<void> _markChannelRead({
    required AuthSession session,
    required String channelId,
  }) async {
    await _api.viewChannel(userId: session.userId, channelId: channelId);
    try {
      await _viewedChannelPosts.removeChannel(
        session: session,
        channelId: channelId,
      );
      _pendingViewedPreferenceCleanup.remove(channelId);
      _realtimeScope?.viewedPostIdsByChannelId.remove(channelId);
    } on Object {
      _pendingViewedPreferenceCleanup.add(channelId);
    }
  }

  Future<void> _retryViewedPreferenceCleanup(AuthSession session) async {
    for (final String channelId in List<String>.of(
      _pendingViewedPreferenceCleanup,
    )) {
      try {
        await _viewedChannelPosts.removeChannel(
          session: session,
          channelId: channelId,
        );
        _pendingViewedPreferenceCleanup.remove(channelId);
        _realtimeScope?.viewedPostIdsByChannelId.remove(channelId);
      } on Object {
        // The channel read boundary already moved. Keep the cleanup queued
        // without failing an authoritative Inbox refresh.
      }
    }
  }

  Future<void> _cleanupReadChannelPreferences({
    required AuthSession session,
    required ViewedChannelPostsSnapshot viewedChannelPosts,
    required Map<String, MattermostChannelDto> channels,
    required Map<String, MattermostChannelMemberDto> members,
  }) async {
    for (final String channelId in viewedChannelPosts.postIdsByChannelId.keys) {
      final MattermostChannelDto? channel = channels[channelId];
      final MattermostChannelMemberDto? member = members[channelId];
      if (channel == null ||
          member == null ||
          channel.type == 'D' ||
          channel.type == 'G' ||
          channel.totalMessageCountRoot > member.msgCountRoot ||
          _pendingViewedPreferenceCleanup.contains(channelId)) {
        continue;
      }
      try {
        await _viewedChannelPosts.removeChannel(
          session: session,
          channelId: channelId,
        );
        _realtimeScope?.viewedPostIdsByChannelId.remove(channelId);
      } on Object {
        _pendingViewedPreferenceCleanup.add(channelId);
      }
    }
  }

  Future<Map<String, SidebarChannel>> _resolveKnownChannels({
    required Map<String, MattermostChannelDto> rawChannels,
    required String currentUserId,
  }) async {
    final List<SidebarChannel> channels = rawChannels.values
        .map(_mapKnownChannel)
        .whereType<SidebarChannel>()
        .toList(growable: false);
    final Set<String> directParticipantIds = channels
        .where(
          (SidebarChannel channel) => channel.kind == ChannelKind.directMessage,
        )
        .map(
          (SidebarChannel channel) => directParticipantId(
            channelName: channel.name,
            currentUserId: currentUserId,
          ),
        )
        .whereType<String>()
        .toSet();
    final List<SidebarChannel> groupChannels = channels
        .where(
          (SidebarChannel channel) => channel.kind == ChannelKind.groupMessage,
        )
        .toList(growable: false);
    try {
      final List<MattermostUserDto> directUsers = directParticipantIds.isEmpty
          ? const <MattermostUserDto>[]
          : await _api.getUsersByIds(directParticipantIds.toList());
      final MattermostGroupChannelUsersDto groupUsers = groupChannels.isEmpty
          ? const MattermostGroupChannelUsersDto(
              usersByChannelId: <String, List<MattermostUserDto>>{},
            )
          : await _api.getUsersForGroupChannels(
              groupChannels
                  .map((SidebarChannel channel) => channel.id)
                  .toList(growable: false),
            );
      final List<SidebarChannel> resolved = resolveDialogDisplayNames(
        channels: channels,
        currentUserId: currentUserId,
        directUsersById: <String, UserSummary>{
          for (final MattermostUserDto user in directUsers)
            if (user.id.isNotEmpty) user.id: mapUserSummary(user),
        },
        groupUsersByChannelId: groupUsers.usersByChannelId.map(
          (String channelId, List<MattermostUserDto> users) =>
              MapEntry<String, List<UserSummary>>(
                channelId,
                users.map(mapUserSummary).toList(growable: false),
              ),
        ),
      );
      return <String, SidebarChannel>{
        for (final SidebarChannel channel in resolved) channel.id: channel,
      };
    } on Object {
      return <String, SidebarChannel>{
        for (final SidebarChannel channel in channels) channel.id: channel,
      };
    }
  }

  SidebarChannel? _mapKnownChannel(MattermostChannelDto channel) {
    try {
      return mapChannel(channel);
    } on FormatException {
      return null;
    }
  }

  static bool _isTrue(JsonValueDto? value) => switch (value) {
    JsonBooleanDto(:final value) => value,
    JsonStringDto(:final value) => value == 'true',
    _ => false,
  };

  static Iterable<List<String>> _batches(List<String> values) sync* {
    for (var start = 0; start < values.length; start += _authorBatchSize) {
      yield values.sublist(
        start,
        start + _authorBatchSize > values.length
            ? values.length
            : start + _authorBatchSize,
      );
    }
  }
}

final class _TeamThreads {
  const _TeamThreads(this.teamId, this.threads);

  final String teamId;
  final List<MattermostUserThreadDto> threads;
}

final class _ThreadSource {
  const _ThreadSource({required this.teamId, required this.raw});

  final String teamId;
  final MattermostUserThreadDto raw;
}

final class _TeamChannels {
  const _TeamChannels({required this.channels, required this.members});

  final List<MattermostChannelDto> channels;
  final List<MattermostChannelMemberDto> members;
}

final class _UnreadChannelPosts {
  const _UnreadChannelPosts(this.channelId, this.posts);

  final String channelId;
  final List<MattermostPostDto> posts;
}

final class _EmptyViewedChannelPostsRepository
    extends ViewedChannelPostsRepository {
  const _EmptyViewedChannelPostsRepository();

  @override
  Future<ViewedChannelPostsSnapshot> load({
    required AuthSession session,
  }) async => ViewedChannelPostsSnapshot(const <String, Set<String>>{});

  @override
  Future<void> add({
    required AuthSession session,
    required String channelId,
    required String postId,
  }) async {}

  @override
  Future<void> removeChannel({
    required AuthSession session,
    required String channelId,
  }) async {}
}

final class _InboxRealtimeScope {
  _InboxRealtimeScope({
    required this.currentUser,
    required this.channels,
    required this.members,
    required this.authors,
    required this.groupMentionNames,
    required this.viewedPostIdsByChannelId,
  });

  final MattermostUserDto currentUser;
  final Map<String, SidebarChannel> channels;
  final Map<String, MattermostChannelMemberDto> members;
  final Map<String, UserSummary> authors;
  final Set<String> groupMentionNames;
  final Map<String, Set<String>> viewedPostIdsByChannelId;
}
