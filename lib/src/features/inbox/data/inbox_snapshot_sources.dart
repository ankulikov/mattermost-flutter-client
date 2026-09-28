import 'dart:collection';

import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/user_mapper.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/message_mapper.dart';
import 'package:mattermost_flutter/src/features/inbox/data/inbox_context_loader.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_completeness.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_notification_settings.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_source_result.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/canonicalize_inbox_candidates.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/classify_inbox_attention.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/group_direct_messages.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/notification_eligibility.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';

/// A transport-backed input to one atomic Inbox projection.
abstract interface class InboxSnapshotSource {
  InboxSourceScope get scope;

  Future<InboxSourceResult> load({
    required AuthSession session,
    required InboxSnapshotContext context,
    required InboxSourceMapper mapper,
  });
}

/// Per-snapshot message mapping scope shared by all source adapters.
///
/// The context itself remains immutable; this object only coalesces author
/// lookups and retains bot metadata needed while constructing candidates.
final class InboxSourceMapper {
  InboxSourceMapper({
    required MattermostApi api,
    required MessageMapper<MattermostPostDto, UserSummary> messageMapper,
  }) : _api = api,
       _messageMapper = messageMapper;

  static const int _authorBatchSize = 100;

  final MattermostApi _api;
  final MessageMapper<MattermostPostDto, UserSummary> _messageMapper;
  final Map<String, UserSummary> _authors = <String, UserSummary>{};
  final Map<String, bool> _rawUsersAreBots = <String, bool>{};

  Map<String, UserSummary> get authors =>
      UnmodifiableMapView<String, UserSummary>(_authors);
  Map<String, bool> get rawUsersAreBots =>
      UnmodifiableMapView<String, bool>(_rawUsersAreBots);

  Future<Map<String, ChannelPost>> mapPosts({
    required Iterable<MattermostPostDto> rawPosts,
    required String currentUserId,
  }) async {
    final List<MattermostPostDto> posts = rawPosts.toList(growable: false);
    final Set<String> unknownAuthorIds = posts
        .map((MattermostPostDto post) => post.userId)
        .where((String id) => id.isNotEmpty && !_authors.containsKey(id))
        .toSet();
    for (final List<String> batch in _batches(unknownAuthorIds.toList())) {
      final List<MattermostUserDto> users = await _api.getUsersByIds(batch);
      for (final MattermostUserDto user in users) {
        _authors[user.id] = mapUserSummary(user);
        _rawUsersAreBots[user.id] = user.isBot;
      }
    }
    return <String, ChannelPost>{
      for (final ChannelPost post in _messageMapper.map(
        posts: posts,
        users: _authors.values,
        currentUserId: currentUserId,
        includeDeleted: true,
      ))
        post.id: post,
    };
  }

  bool isBot(String userId) => _rawUsersAreBots[userId] == true;

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

/// Loads unread followed CRT threads for all teams and maps them to candidates.
final class InboxFollowedThreadsSource implements InboxSnapshotSource {
  InboxFollowedThreadsSource({required MattermostApi api}) : _api = api;

  static const int _maxTeamConcurrency = 4;
  static const int _maxUnreadThreadPages = 8;

  final MattermostApi _api;

  @override
  InboxSourceScope get scope => InboxSourceScope.followedThreads;

  @override
  Future<InboxSourceResult> load({
    required AuthSession session,
    required InboxSnapshotContext context,
    required InboxSourceMapper mapper,
  }) async {
    final List<_TeamThreads> pages = await _loadUnreadThreadsForTeams(
      teams: context.teams,
      userId: session.userId,
    );
    final Map<String, _ThreadSource> threads = <String, _ThreadSource>{};
    for (final _TeamThreads page in pages) {
      for (final MattermostUserThreadDto thread in page.threads) {
        if (thread.post == null ||
            thread.deleteAt != 0 ||
            thread.post!.deleteAt != 0 ||
            !_isThreadEligible(thread, context)) {
          continue;
        }
        threads.putIfAbsent(
          thread.id,
          () => _ThreadSource(teamId: page.teamId, raw: thread),
        );
      }
    }
    final Map<String, ChannelPost> mappedById = await mapper.mapPosts(
      rawPosts: threads.values
          .map((_ThreadSource source) => source.raw.post)
          .whereType<MattermostPostDto>(),
      currentUserId: session.userId,
    );
    final List<InboxThreadCandidate> candidates = threads.values
        .map(
          (_ThreadSource source) => _mapThread(
            source: source,
            mappedById: mappedById,
            context: context,
          ),
        )
        .whereType<InboxThreadCandidate>()
        .toList(growable: false);
    return InboxSourceResult(
      candidates: InboxSourceSnapshot(threads: candidates),
      completeness: InboxCompleteness.mostLimited(
        pages.map((_TeamThreads page) => page.completeness),
      ),
    );
  }

  Future<List<_TeamThreads>> _loadUnreadThreadsForTeams({
    required List<MattermostTeamDto> teams,
    required String userId,
  }) async {
    final List<_TeamThreads> result = <_TeamThreads>[];
    for (var start = 0; start < teams.length; start += _maxTeamConcurrency) {
      final List<MattermostTeamDto> batch = teams.sublist(
        start,
        start + _maxTeamConcurrency > teams.length
            ? teams.length
            : start + _maxTeamConcurrency,
      );
      result.addAll(
        await Future.wait(
          batch.map(
            (MattermostTeamDto team) =>
                _loadUnreadThreads(userId: userId, teamId: team.id),
          ),
        ),
      );
    }
    return result;
  }

  Future<_TeamThreads> _loadUnreadThreads({
    required String userId,
    required String teamId,
  }) async {
    final List<MattermostUserThreadDto> result = <MattermostUserThreadDto>[];
    String? before;
    final Set<String> cursors = <String>{};
    for (var pageCount = 0; pageCount < _maxUnreadThreadPages; pageCount++) {
      final MattermostUserThreadsDto page = await _api.getUserThreads(
        userId: userId,
        teamId: teamId,
        before: before,
        unread: true,
      );
      result.addAll(page.threads);
      if (page.threads.length < 60) return _TeamThreads(teamId, result);
      final String next = page.threads.last.id;
      if (!cursors.add(next)) {
        return _TeamThreads(
          teamId,
          result,
          completeness: InboxCompleteness.truncated,
        );
      }
      before = next;
    }
    return _TeamThreads(
      teamId,
      result,
      completeness: InboxCompleteness.truncated,
    );
  }

  InboxThreadCandidate? _mapThread({
    required _ThreadSource source,
    required Map<String, ChannelPost> mappedById,
    required InboxSnapshotContext context,
  }) {
    final MattermostUserThreadDto raw = source.raw;
    final ChannelPost? root = raw.post == null
        ? null
        : mappedById[raw.post!.id];
    final SidebarChannel? channel = root == null
        ? null
        : context.channels[root.channelId];
    if (root == null || channel == null) return null;
    final MattermostChannelMemberDto? member = context.members[root.channelId];
    final InboxAttentionReason? rootReason = channel.isDialog
        ? InboxAttentionReason.allMessagesSubscription
        : member == null || raw.post == null
        ? null
        : _classify(raw.post!, context.currentUser, member);
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

  bool _isThreadEligible(
    MattermostUserThreadDto thread,
    InboxSnapshotContext context,
  ) {
    final MattermostPostDto? root = thread.post;
    if (root == null || root.deleteAt != 0) return false;
    final MattermostChannelMemberDto? member = context.members[root.channelId];
    return member != null &&
        isFollowedThreadInboxEligible(
          channel: _channelNotificationSettings(member),
          user: _userNotificationSettings(context.currentUser),
          unreadReplies: thread.unreadReplies,
          unreadMentions: thread.unreadMentions,
        );
  }
}

/// Coalesces the DM/GM, reconstructed-mention, and desktop-all REST ranges.
///
/// These logical sources share the same unread endpoint and membership gate;
/// a single adapter intentionally owns that request so adding source labels
/// cannot duplicate a channel's unread range fetch.
final class InboxUnreadChannelPostsSource implements InboxSnapshotSource {
  InboxUnreadChannelPostsSource({required MattermostApi api}) : _api = api;

  static const int _maxUnreadConcurrency = 4;
  static const int _unreadRangePageSize = 200;
  static const int _maxUnreadRangePages = 8;
  final MattermostApi _api;

  @override
  InboxSourceScope get scope => InboxSourceScope.unreadChannelPosts;

  @override
  Future<InboxSourceResult> load({
    required AuthSession session,
    required InboxSnapshotContext context,
    required InboxSourceMapper mapper,
  }) async {
    final List<_UnreadChannelPosts> unread = await _loadUnreadPosts(context);
    final Map<String, ChannelPost> mappedById = await mapper.mapPosts(
      rawPosts: unread.expand((_UnreadChannelPosts source) => source.posts),
      currentUserId: session.userId,
    );
    final List<InboxPostCandidate> candidates = <InboxPostCandidate>[];
    var incompleteMentions = false;
    final Set<InboxSourceDiagnosticCode> diagnostics =
        <InboxSourceDiagnosticCode>{
          for (final _UnreadChannelPosts entry in unread)
            ...entry.diagnosticsCodes,
        };
    for (final _UnreadChannelPosts entry in unread) {
      final SidebarChannel? channel = context.channels[entry.channelId];
      final MattermostChannelMemberDto? member =
          context.members[entry.channelId];
      if (channel == null || member == null) continue;
      var reconstructedMentions = 0;
      for (final MattermostPostDto raw in entry.posts) {
        final ChannelPost? mapped = mappedById[raw.id];
        if (mapped == null || raw.userId == session.userId) continue;
        final InboxAttentionReason? reason = _attentionReason(
          raw: raw,
          channel: channel,
          member: member,
          user: context.currentUser,
        );
        if (reason == null) continue;
        if (reason != InboxAttentionReason.allMessagesSubscription) {
          reconstructedMentions++;
        }
        candidates.add(
          InboxPostCandidate(
            post: mapped,
            channel: channel,
            reason: reason,
            isSystem: raw.type.startsWith('system_'),
            isSilentNotification: _isTrue(
              raw.props?.values['silent_notification'],
            ),
            isFromBot: mapper.isBot(raw.userId),
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
    final InboxCompleteness rangeCompleteness = InboxCompleteness.mostLimited(
      unread.map((_UnreadChannelPosts entry) => entry.completeness),
    );
    if (incompleteMentions) {
      diagnostics.add(InboxSourceDiagnosticCode.mentionReconstructionMismatch);
    }
    return InboxSourceResult(
      candidates: InboxSourceSnapshot(posts: candidates),
      completeness: InboxCompleteness.mostLimited(<InboxCompleteness>[
        rangeCompleteness,
        if (incompleteMentions) InboxCompleteness.approximateMentions,
      ]),
      diagnosticsCodes: diagnostics,
    );
  }

  Future<List<_UnreadChannelPosts>> _loadUnreadPosts(
    InboxSnapshotContext context,
  ) async {
    final List<String> ids = context.rawChannels.keys
        .where((String id) {
          final MattermostChannelDto channel = context.rawChannels[id]!;
          final MattermostChannelMemberDto? member = context.members[id];
          return member != null &&
              _shouldLoadUnreadPosts(channel, member, context.currentUser);
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
            final MattermostChannelMemberDto member =
                context.members[channelId]!;
            final MattermostChannelDto channel =
                context.rawChannels[channelId]!;
            return _loadUnreadChannelRange(channel: channel, member: member);
          }),
        ),
      );
    }
    return result;
  }

  /// Completes the bounded unread endpoint through the ordinary post cursor.
  ///
  /// Mattermost bounds `/posts/unread` to [limitAfter]. The follow-up cursor
  /// must come from `PostList.order`, rather than map iteration, so servers
  /// with a different JSON map order cannot make us skip or repeat a page.
  /// We stop once the membership counter is covered, otherwise return a typed
  /// truncated result rather than presenting the first 200 posts as complete.
  Future<_UnreadChannelPosts> _loadUnreadChannelRange({
    required MattermostChannelDto channel,
    required MattermostChannelMemberDto member,
  }) async {
    final MattermostPostListDto first = await _api.getUnreadPostsForChannel(
      userId: member.userId,
      channelId: channel.id,
      limitAfter: _unreadRangePageSize,
    );
    final List<MattermostPostDto> posts = <MattermostPostDto>[];
    final Set<String> postIds = <String>{};
    _addUnreadPosts(
      target: posts,
      postIds: postIds,
      page: first,
      lastViewedAt: member.lastViewedAt,
    );

    final int expectedUnreadCount = _expectedUnreadCount(channel, member);
    if (_countUnreadForCounter(posts, channel) >= expectedUnreadCount) {
      return _UnreadChannelPosts(channel.id, posts);
    }

    final Set<String> cursors = <String>{};
    // `/posts/unread` is anchored at the oldest unread post and `limit_after`
    // advances toward newer activity. `PostList.order` is newest-first, so the
    // cursor must be its first raw ID; using the oldest ID with `before` would
    // walk back into already-read history instead of completing this range.
    String? cursor = _newestPostId(first);
    var pageCount = 1;
    while (_countUnreadForCounter(posts, channel) < expectedUnreadCount) {
      if (pageCount >= _maxUnreadRangePages) {
        return _UnreadChannelPosts(
          channel.id,
          posts,
          completeness: InboxCompleteness.truncated,
          diagnosticsCodes: const <InboxSourceDiagnosticCode>[
            InboxSourceDiagnosticCode.unreadRangeSafetyCapReached,
          ],
        );
      }
      if (cursor == null || cursor.isEmpty) {
        return _truncatedUnreadRange(
          channelId: channel.id,
          posts: posts,
          diagnostic: InboxSourceDiagnosticCode.unreadRangeCounterMismatch,
        );
      }
      if (!cursors.add(cursor)) {
        return _truncatedUnreadRange(
          channelId: channel.id,
          posts: posts,
          diagnostic: InboxSourceDiagnosticCode.unreadRangeCursorLoopDetected,
        );
      }

      final MattermostPostListDto page = await _api.getPostsAfter(
        channelId: channel.id,
        postId: cursor,
        perPage: _unreadRangePageSize,
      );
      pageCount++;
      final int beforeCount = posts.length;
      _addUnreadPosts(
        target: posts,
        postIds: postIds,
        page: page,
        lastViewedAt: member.lastViewedAt,
      );
      if (posts.length == beforeCount) {
        return _truncatedUnreadRange(
          channelId: channel.id,
          posts: posts,
          diagnostic: InboxSourceDiagnosticCode.unreadRangeCursorLoopDetected,
        );
      }
      cursor = _newestPostId(page);
    }
    return _UnreadChannelPosts(channel.id, posts);
  }

  _UnreadChannelPosts _truncatedUnreadRange({
    required String channelId,
    required List<MattermostPostDto> posts,
    required InboxSourceDiagnosticCode diagnostic,
  }) => _UnreadChannelPosts(
    channelId,
    posts,
    completeness: InboxCompleteness.truncated,
    diagnosticsCodes: <InboxSourceDiagnosticCode>[diagnostic],
  );

  static void _addUnreadPosts({
    required List<MattermostPostDto> target,
    required Set<String> postIds,
    required MattermostPostListDto page,
    required int lastViewedAt,
  }) {
    for (final String id in page.order) {
      final MattermostPostDto? post = page.posts[id];
      if (post != null &&
          post.createAt > lastViewedAt &&
          postIds.add(post.id)) {
        target.add(post);
      }
    }
  }

  static String? _newestPostId(MattermostPostListDto page) =>
      page.order.isEmpty ? null : page.order.first;

  static int _expectedUnreadCount(
    MattermostChannelDto channel,
    MattermostChannelMemberDto member,
  ) => channel.type == 'D' || channel.type == 'G'
      ? (channel.totalMessageCount - member.msgCount).clamp(0, 1 << 31)
      : (channel.totalMessageCountRoot - member.msgCountRoot).clamp(0, 1 << 31);

  static int _countUnreadForCounter(
    Iterable<MattermostPostDto> posts,
    MattermostChannelDto channel,
  ) => channel.type == 'D' || channel.type == 'G'
      ? posts.length
      : posts.where((MattermostPostDto post) => post.rootId.isEmpty).length;

  bool _shouldLoadUnreadPosts(
    MattermostChannelDto channel,
    MattermostChannelMemberDto member,
    MattermostUserDto currentUser,
  ) {
    final bool dialog = channel.type == 'D' || channel.type == 'G';
    final InboxChannelNotificationSettings notificationSettings =
        _channelNotificationSettings(member);
    final InboxUserNotificationSettings userSettings =
        _userNotificationSettings(currentUser);
    if (dialog) {
      return channel.totalMessageCount > member.msgCount &&
          isDirectMessageInboxEligible(
            channel: notificationSettings,
            user: userSettings,
          );
    }
    if (resolveInboxDesktopNotificationLevel(
          channel: notificationSettings.desktop,
          user: userSettings.desktop,
        ) ==
        InboxDesktopNotificationLevel.none) {
      return false;
    }
    final bool hasUnreadRoots =
        channel.totalMessageCountRoot > member.msgCountRoot;
    if (!hasUnreadRoots) return false;
    if (member.mentionCountRoot > 0) return true;
    return resolvesToAllMessagesSubscription(
      channel: notificationSettings,
      user: userSettings,
    );
  }
}

/// Hydrates durable postponed references without adding them to the New source.
final class InboxPostponedSource implements InboxSnapshotSource {
  InboxPostponedSource({
    required MattermostApi api,
    required PostponedRepository postponed,
  }) : _api = api,
       _postponed = postponed;

  static const int _batchSize = 100;
  final MattermostApi _api;
  final PostponedRepository _postponed;

  @override
  InboxSourceScope get scope => InboxSourceScope.postponed;

  @override
  Future<InboxSourceResult> load({
    required AuthSession session,
    required InboxSnapshotContext context,
    required InboxSourceMapper mapper,
  }) async {
    final PostponedReferencesSnapshot postponed = await _postponed.load(
      session: session,
    );
    final Set<String> ids = postponed.references
        .map((PostponedReference reference) => reference.postId)
        .toSet();
    final Map<String, MattermostPostDto> rawPosts =
        <String, MattermostPostDto>{};
    var hydrationUnavailable = false;
    for (final List<String> batch in _batches(ids.toList())) {
      try {
        for (final MattermostPostDto post in await _api.getPostsByIds(batch)) {
          rawPosts[post.id] = post;
        }
      } on RequestCancelledException {
        rethrow;
      } on Object {
        hydrationUnavailable = true;
      }
    }
    Map<String, ChannelPost> mappedById = <String, ChannelPost>{};
    try {
      mappedById = await mapper.mapPosts(
        rawPosts: rawPosts.values,
        currentUserId: session.userId,
      );
    } on RequestCancelledException {
      rethrow;
    } on Object {
      hydrationUnavailable = true;
    }
    final List<InboxItem> postponedItems = _postponedItems(
      references: postponed.references,
      rawPosts: rawPosts,
      mappedById: mappedById,
      context: context,
      mapper: mapper,
    );
    return InboxSourceResult(
      candidates: InboxSourceSnapshot(),
      postponedItems: postponedItems,
      diagnosticsCodes:
          hydrationUnavailable ||
              postponedItems.any(
                (InboxItem item) => item is UnavailablePostponedInboxItem,
              )
          ? const <InboxSourceDiagnosticCode>[
              InboxSourceDiagnosticCode.postponedHydrationUnavailable,
            ]
          : const <InboxSourceDiagnosticCode>[],
    );
  }

  List<InboxItem> _postponedItems({
    required List<PostponedReference> references,
    required Map<String, MattermostPostDto> rawPosts,
    required Map<String, ChannelPost> mappedById,
    required InboxSnapshotContext context,
    required InboxSourceMapper mapper,
  }) {
    final List<InboxPostCandidate> posts = <InboxPostCandidate>[];
    final List<InboxItem> threads = <InboxItem>[];
    final List<InboxItem> unavailable = <InboxItem>[];
    for (final PostponedReference reference in references) {
      final MattermostPostDto? raw = rawPosts[reference.postId];
      final ChannelPost? post = mappedById[reference.postId];
      final SidebarChannel? channel = raw == null
          ? null
          : context.channels[raw.channelId];
      if (raw == null || post == null || channel == null) {
        unavailable.add(UnavailablePostponedInboxItem(reference: reference));
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
            isFromBot: mapper.isBot(raw.userId),
            isFromWebhook: _isTrue(raw.props?.values['from_webhook']),
            isFromPlugin: _isTrue(raw.props?.values['from_plugin']),
          ),
        );
      }
    }
    final List<InboxItem> grouped = groupDirectMessages(
      canonicalizeInboxCandidates(InboxSourceSnapshot(posts: posts)),
    ).map((InboxItem item) => _withPostponedAt(item, references)).toList();
    return <InboxItem>[...threads, ...grouped, ...unavailable];
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
      UnavailablePostponedInboxItem() => item,
    };
  }

  static Iterable<List<String>> _batches(List<String> values) sync* {
    for (var start = 0; start < values.length; start += _batchSize) {
      yield values.sublist(
        start,
        start + _batchSize > values.length ? values.length : start + _batchSize,
      );
    }
  }
}

InboxAttentionReason? _classify(
  MattermostPostDto post,
  MattermostUserDto user,
  MattermostChannelMemberDto member,
) {
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
    allMessagesSubscription: resolvesToAllMessagesSubscription(
      channel: _channelNotificationSettings(member),
      user: _userNotificationSettings(user),
    ),
  );
}

InboxAttentionReason? _attentionReason({
  required MattermostPostDto raw,
  required SidebarChannel channel,
  required MattermostChannelMemberDto member,
  required MattermostUserDto user,
}) {
  final InboxChannelNotificationSettings notificationSettings =
      _channelNotificationSettings(member);
  final InboxUserNotificationSettings userSettings = _userNotificationSettings(
    user,
  );
  if (channel.isDialog) {
    return isDirectMessageInboxEligible(
          channel: notificationSettings,
          user: userSettings,
        )
        ? InboxAttentionReason.allMessagesSubscription
        : null;
  }
  if (resolveInboxDesktopNotificationLevel(
        channel: notificationSettings.desktop,
        user: userSettings.desktop,
      ) ==
      InboxDesktopNotificationLevel.none) {
    return null;
  }
  return _classify(raw, user, member);
}

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

bool _isTrue(JsonValueDto? value) => switch (value) {
  JsonBooleanDto(:final value) => value,
  JsonStringDto(:final value) => value == 'true',
  _ => false,
};

final class _TeamThreads {
  const _TeamThreads(
    this.teamId,
    this.threads, {
    this.completeness = InboxCompleteness.exact,
  });

  final String teamId;
  final List<MattermostUserThreadDto> threads;
  final InboxCompleteness completeness;
}

final class _ThreadSource {
  const _ThreadSource({required this.teamId, required this.raw});

  final String teamId;
  final MattermostUserThreadDto raw;
}

final class _UnreadChannelPosts {
  _UnreadChannelPosts(
    this.channelId,
    Iterable<MattermostPostDto> posts, {
    this.completeness = InboxCompleteness.exact,
    Iterable<InboxSourceDiagnosticCode> diagnosticsCodes =
        const <InboxSourceDiagnosticCode>[],
  }) : posts = List<MattermostPostDto>.unmodifiable(posts),
       diagnosticsCodes = Set<InboxSourceDiagnosticCode>.unmodifiable(
         diagnosticsCodes,
       );

  final String channelId;
  final List<MattermostPostDto> posts;
  final InboxCompleteness completeness;
  final Set<InboxSourceDiagnosticCode> diagnosticsCodes;
}
