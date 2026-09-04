import 'dart:async';

import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/channel_sidebar_mapper.dart';
import 'package:mattermost_flutter/src/data/mappers/user_mapper.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/message_mapper.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/canonicalize_inbox_candidates.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/classify_inbox_attention.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/group_direct_messages.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/notification_eligibility.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/reconcile_queues.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';

/// REST-only, network-first Inbox snapshot builder.
///
/// Realtime events and sequence-gap recovery deliberately remain outside this
/// MVP repository; a controller can replace this full snapshot atomically.
final class MattermostInboxRepository extends InboxRepository {
  MattermostInboxRepository({
    required MattermostApi api,
    required MessageMapper<MattermostPostDto, UserSummary> messageMapper,
    required PostponedRepository postponed,
    DateTime Function()? now,
  }) : _api = api,
       _messageMapper = messageMapper,
       _postponed = postponed,
       _now = now ?? DateTime.now;

  static const int _authorBatchSize = 100;
  static const int _maxUnreadConcurrency = 4;

  final MattermostApi _api;
  final MessageMapper<MattermostPostDto, UserSummary> _messageMapper;
  final PostponedRepository _postponed;
  final DateTime Function() _now;

  @override
  Future<InboxSnapshot> load({required AuthSession session}) async {
    final DateTime builtAt = _now();
    final MattermostUserDto currentUser = await _api.getCurrentUser();
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

    final List<List<MattermostUserThreadDto>> unreadThreadPages =
        await Future.wait(
          teams.map(
            (MattermostTeamDto team) =>
                _loadUnreadThreads(userId: session.userId, teamId: team.id),
          ),
        );
    final Map<String, MattermostUserThreadDto> rawThreads =
        <String, MattermostUserThreadDto>{};
    for (final MattermostUserThreadDto thread in unreadThreadPages.expand(
      (List<MattermostUserThreadDto> page) => page,
    )) {
      if (thread.post == null ||
          thread.deleteAt != 0 ||
          thread.unreadReplies <= 0) {
        continue;
      }
      rawThreads.putIfAbsent(thread.id, () => thread);
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
      for (final MattermostUserThreadDto thread in rawThreads.values)
        if (thread.post != null) thread.post!.id: thread.post!,
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
        .map((MattermostUserThreadDto raw) => _mapThread(raw, mappedById))
        .whereType<InboxThreadCandidate>()
        .toList(growable: false);
    final List<InboxPostCandidate> newCandidates = <InboxPostCandidate>[];
    var incompleteMentions = false;
    for (final _UnreadChannelPosts entry in unread) {
      final SidebarChannel? channel = _mapKnownChannel(
        channels[entry.channelId],
      );
      final MattermostChannelMemberDto? member = members[entry.channelId];
      if (channel == null || member == null) continue;
      var reconstructedMentions = 0;
      for (final MattermostPostDto raw in entry.posts) {
        final ChannelPost? mapped = mappedById[raw.id];
        if (mapped == null || raw.userId == session.userId) continue;
        final InboxAttentionReason? reason = channel.isDialog
            ? InboxAttentionReason.allMessagesSubscription
            : _classify(raw, currentUser, member);
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
      channels: channels,
      authors: authors,
    );
    // TODO(inbox): API v4 counters cannot identify all historical mentions;
    // group mentions and @here require server-side delivery context.
    final List<InboxItem> newItems = groupDirectMessages(
      canonicalizeInboxCandidates(
        InboxSourceSnapshot(threads: threadCandidates, posts: newCandidates),
      ),
    );
    return reconcileQueues(
      newItems: newItems,
      postponedItems: postponedItems,
      builtAt: builtAt,
      hasIncompleteMentionReconstruction: incompleteMentions,
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
        memberMarkUnread: notify.markUnread,
        memberDesktop: notify.desktop,
        memberPush: notify.push,
        userDesktop: userNotify.desktop,
        userPush: userNotify.push,
      ),
    );
  }

  InboxThreadCandidate? _mapThread(
    MattermostUserThreadDto raw,
    Map<String, ChannelPost> mappedById,
  ) {
    final ChannelPost? root = raw.post == null
        ? null
        : mappedById[raw.post!.id];
    if (root == null) return null;
    return InboxThreadCandidate(
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
    required Map<String, MattermostChannelDto> channels,
    required Map<String, UserSummary> authors,
  }) {
    final List<InboxPostCandidate> posts = <InboxPostCandidate>[];
    final List<InboxItem> threads = <InboxItem>[];
    for (final PostponedReference reference in references) {
      final MattermostPostDto? raw = rawPosts[reference.postId];
      final ChannelPost? post = mappedById[reference.postId];
      final SidebarChannel? channel = raw == null
          ? null
          : _mapKnownChannel(channels[raw.channelId]);
      if (raw == null || post == null || channel == null) {
        // TODO(inbox): Domain has no unavailable-post placeholder yet; retain
        // the preference remotely and surface it when a placeholder is added.
        continue;
      }
      if (reference.kind == PostponedReferenceKind.thread) {
        threads.add(
          ThreadInboxItem(
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

  SidebarChannel? _mapKnownChannel(MattermostChannelDto? channel) {
    if (channel == null) return null;
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
