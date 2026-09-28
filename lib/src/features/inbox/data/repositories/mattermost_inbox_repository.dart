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
import 'package:mattermost_flutter/src/features/inbox/domain/policies/canonicalize_inbox_candidates.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/classify_inbox_attention.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/group_direct_messages.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/notification_eligibility.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/reconcile_queues.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
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
    required UserGroupMembershipCache userGroupCache,
    WebSocketGateway? webSocketGateway,
    CredentialStore? credentialStore,
    SessionRealtimeService? realtime,
    DateTime Function()? now,
  }) : _api = api,
       _messageMapper = messageMapper,
       _postponed = postponed,
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
  final UserGroupMembershipCache _userGroupCache;
  final SessionRealtimeService? _realtime;
  final DateTime Function() _now;
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

    final List<_UnreadChannelPosts> unread = await _loadUnreadPosts(
      channels: channels,
      members: members,
      currentUser: currentUser,
    );
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
        final InboxAttentionReason? reason = channel.isDialog
            ? InboxAttentionReason.allMessagesSubscription
            : _classify(
                raw,
                currentUser,
                member,
                groupMentionNames: groupMentionNames,
              );
        if (reason == null) continue;
        if (reason != InboxAttentionReason.allMessagesSubscription) {
          reconstructedMentions++;
        }
        newCandidates.add(
          InboxPostCandidate(
            post: mapped,
            channel: channel,
            reason: reason,
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
    final InboxAttentionReason? reason = channel.isDialog
        ? InboxAttentionReason.allMessagesSubscription
        : _classifyRealtime(
            raw,
            scope.currentUser,
            member,
            groupMentionNames: scope.groupMentionNames,
            serverMentioned: serverMentioned,
          );
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

  InboxAttentionReason? _classifyRealtime(
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
    final InboxAttentionReason? reconstructed = classifyInboxAttention(
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
          ? InboxAttentionReason.allMessagesSubscription
          : null;
    }
    return reconstructed == null ||
            reconstructed == InboxAttentionReason.allMessagesSubscription
        ? InboxAttentionReason.directMention
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

  InboxAttentionReason? _classify(
    MattermostPostDto post,
    MattermostUserDto user,
    MattermostChannelMemberDto member, {
    required Set<String> groupMentionNames,
  }) {
    final MattermostChannelNotifyPropsDto notify =
        member.notifyProps ?? const MattermostChannelNotifyPropsDto();
    final UserNotifyPropsDto userNotify =
        user.notifyProps ?? const UserNotifyPropsDto();
    return classifyInboxAttention(
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
    final InboxAttentionReason? rootReason = channel.isDialog
        ? InboxAttentionReason.allMessagesSubscription
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
      rootAttentionReason: rootReason,
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

  List<InboxItem> _postponedItems({
    required List<PostponedReference> references,
    required Map<String, MattermostPostDto> rawPosts,
    required Map<String, ChannelPost> mappedById,
    required Map<String, SidebarChannel> channels,
    required Map<String, UserSummary> authors,
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
        posts.add(
          InboxPostCandidate(
            post: post,
            channel: channel,
            reason: InboxAttentionReason.allMessagesSubscription,
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
    ChannelPostInboxItem(:final post) => _api.viewChannel(
      userId: session.userId,
      channelId: post.channelId,
    ),
    DirectMessageBundleInboxItem(:final channelId) => _api.viewChannel(
      userId: session.userId,
      channelId: channelId,
    ),
  };

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

final class _InboxRealtimeScope {
  _InboxRealtimeScope({
    required this.currentUser,
    required this.channels,
    required this.members,
    required this.authors,
    required this.groupMentionNames,
  });

  final MattermostUserDto currentUser;
  final Map<String, SidebarChannel> channels;
  final Map<String, MattermostChannelMemberDto> members;
  final Map<String, UserSummary> authors;
  final Set<String> groupMentionNames;
}
