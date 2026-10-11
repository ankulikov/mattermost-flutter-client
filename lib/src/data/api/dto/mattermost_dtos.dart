/// Wire DTOs for the Mattermost API v4 endpoints exposed by [MattermostApi].
///
/// These types deliberately stay in the API layer. Domain entities and database
/// rows must be produced by explicit mappers.
library;

import 'dart:typed_data';

typedef JsonMap = Map<String, Object?>;

/// The public subset of `GET /config/client?format=old` needed before login.
final class MattermostClientConfigDto {
  const MattermostClientConfigDto({
    required this.enableSaml,
    required this.samlLoginButtonText,
    required this.enableSignUpWithOpenId,
    required this.openIdButtonText,
    this.enableSignInWithEmail = false,
    this.enableSignInWithUsername = false,
  });

  factory MattermostClientConfigDto.fromJson(JsonMap json) =>
      MattermostClientConfigDto(
        enableSaml: _bool(json, 'EnableSaml'),
        samlLoginButtonText: _string(json, 'SamlLoginButtonText'),
        enableSignUpWithOpenId: _bool(json, 'EnableSignUpWithOpenId'),
        openIdButtonText: _string(json, 'OpenIdButtonText'),
        enableSignInWithEmail: _bool(json, 'EnableSignInWithEmail'),
        enableSignInWithUsername: _bool(json, 'EnableSignInWithUsername'),
      );

  final bool enableSaml;
  final String samlLoginButtonText;
  final bool enableSignUpWithOpenId;
  final String openIdButtonText;
  final bool enableSignInWithEmail;
  final bool enableSignInWithUsername;
}

final class MattermostUserDto {
  const MattermostUserDto({
    required this.id,
    required this.username,
    this.createAt = 0,
    this.updateAt = 0,
    this.deleteAt = 0,
    this.firstName = '',
    this.lastName = '',
    this.nickname = '',
    this.position = '',
    this.email = '',
    this.emailVerified = false,
    this.authService = '',
    this.roles = '',
    this.locale = '',
    this.notifyProps,
    this.props,
    this.lastPasswordUpdate = 0,
    this.lastPictureUpdate = 0,
    this.isBot = false,
    this.botLastIconUpdate = 0,
    this.failedAttempts = 0,
    this.mfaActive = false,
    this.timezone,
    this.termsOfServiceId,
    this.termsOfServiceCreateAt = 0,
  });

  factory MattermostUserDto.fromJson(JsonMap json) => MattermostUserDto(
    id: _string(json, 'id'),
    username: _string(json, 'username'),
    createAt: _int(json, 'create_at'),
    updateAt: _int(json, 'update_at'),
    deleteAt: _int(json, 'delete_at'),
    firstName: _string(json, 'first_name'),
    lastName: _string(json, 'last_name'),
    nickname: _string(json, 'nickname'),
    position: _string(json, 'position'),
    email: _string(json, 'email'),
    emailVerified: _bool(json, 'email_verified'),
    authService: _string(json, 'auth_service'),
    roles: _string(json, 'roles'),
    locale: _string(json, 'locale'),
    notifyProps: _nested(json, 'notify_props', UserNotifyPropsDto.fromJson),
    props: _nested(json, 'props', UserPropsDto.fromJson),
    lastPasswordUpdate: _int(json, 'last_password_update'),
    lastPictureUpdate: _int(json, 'last_picture_update'),
    isBot: _bool(json, 'is_bot'),
    botLastIconUpdate: _int(json, 'bot_last_icon_update'),
    failedAttempts: _int(json, 'failed_attempts'),
    mfaActive: _bool(json, 'mfa_active'),
    timezone: _nested(json, 'timezone', MattermostTimezoneDto.fromJson),
    termsOfServiceId: _nullableString(json, 'terms_of_service_id'),
    termsOfServiceCreateAt: _int(json, 'terms_of_service_create_at'),
  );

  final String id;
  final int createAt;
  final int updateAt;
  final int deleteAt;
  final String username;
  final String firstName;
  final String lastName;
  final String nickname;
  final String position;
  final String email;
  final bool emailVerified;
  final String authService;
  final String roles;
  final String locale;
  final UserNotifyPropsDto? notifyProps;
  final UserPropsDto? props;
  final int lastPasswordUpdate;
  final int lastPictureUpdate;
  final bool isBot;
  final int botLastIconUpdate;
  final int failedAttempts;
  final bool mfaActive;
  final MattermostTimezoneDto? timezone;
  final String? termsOfServiceId;
  final int termsOfServiceCreateAt;

  int get profileImageUpdatedAt =>
      isBot ? botLastIconUpdate : lastPictureUpdate;
}

/// Wire response for `GET /users/autocomplete`.
///
/// The server always returns [users]. Older servers may omit the additional
/// sections, so they remain nullable rather than being fabricated client-side.
final class MattermostUserAutocompleteDto {
  const MattermostUserAutocompleteDto({
    required this.users,
    this.outOfChannel,
    this.agents,
  });

  factory MattermostUserAutocompleteDto.fromJson(JsonMap json) =>
      MattermostUserAutocompleteDto(
        users: _dtoList(json, 'users', MattermostUserDto.fromJson),
        outOfChannel: json.containsKey('out_of_channel')
            ? _dtoList(json, 'out_of_channel', MattermostUserDto.fromJson)
            : null,
        agents: json.containsKey('agents')
            ? _dtoList(json, 'agents', MattermostUserDto.fromJson)
            : null,
      );

  final List<MattermostUserDto> users;
  final List<MattermostUserDto>? outOfChannel;
  final List<MattermostUserDto>? agents;
}

/// Wire projection returned by Mattermost user-group endpoints.
final class MattermostGroupDto {
  const MattermostGroupDto({
    required this.id,
    required this.name,
    required this.displayName,
    this.deleteAt = 0,
    this.allowReference = false,
    this.memberCount = 0,
  });

  factory MattermostGroupDto.fromJson(JsonMap json) => MattermostGroupDto(
    id: _string(json, 'id'),
    name: _string(json, 'name'),
    displayName: _string(json, 'display_name'),
    deleteAt: _int(json, 'delete_at'),
    allowReference: _bool(json, 'allow_reference'),
    memberCount: _int(json, 'member_count'),
  );

  final String id;
  final String name;
  final String displayName;
  final int deleteAt;
  final bool allowReference;
  final int memberCount;
}

final class MattermostUserStatusDto {
  const MattermostUserStatusDto({
    required this.userId,
    required this.status,
    this.manual = false,
    this.lastActivityAt = 0,
    this.dndEndTime = 0,
  });

  factory MattermostUserStatusDto.fromJson(JsonMap json) =>
      MattermostUserStatusDto(
        userId: _string(json, 'user_id'),
        status: _string(json, 'status'),
        manual: _bool(json, 'manual'),
        lastActivityAt: _int(json, 'last_activity_at'),
        dndEndTime: _int(json, 'dnd_end_time'),
      );

  final String userId;
  final String status;
  final bool manual;
  final int lastActivityAt;
  final int dndEndTime;
}

final class MattermostCustomStatusRequestDto {
  const MattermostCustomStatusRequestDto({
    required this.emoji,
    required this.text,
    required this.duration,
    required this.expiresAt,
  });

  final String emoji;
  final String text;
  final String duration;
  final DateTime expiresAt;

  JsonMap toJson() => <String, Object?>{
    'emoji': emoji,
    'text': text,
    'duration': duration,
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };
}

/// Binary response returned by the user profile-image endpoint.
final class MattermostImageDto {
  const MattermostImageDto({required this.bytes, this.contentType});

  final Uint8List bytes;
  final String? contentType;
}

final class MattermostFileContentDto {
  const MattermostFileContentDto({required this.bytes, this.contentType});

  final Uint8List bytes;
  final String? contentType;
}

final class UserNotifyPropsDto {
  const UserNotifyPropsDto({
    this.email = '',
    this.push = '',
    this.desktop = '',
    this.desktopSound = '',
    this.mentionKeys = '',
    this.channel = '',
    this.firstName = '',
    this.comments = '',
    this.desktopThreads = '',
    this.pushThreads = '',
    this.emailThreads = '',
    this.channelMentionAutoFollowThreads = '',
  });

  factory UserNotifyPropsDto.fromJson(JsonMap json) => UserNotifyPropsDto(
    email: _string(json, 'email'),
    push: _string(json, 'push'),
    desktop: _string(json, 'desktop'),
    desktopSound: _string(json, 'desktop_sound'),
    mentionKeys: _string(json, 'mention_keys'),
    channel: _string(json, 'channel'),
    firstName: _string(json, 'first_name'),
    comments: _string(json, 'comments'),
    desktopThreads: _string(json, 'desktop_threads'),
    pushThreads: _string(json, 'push_threads'),
    emailThreads: _string(json, 'email_threads'),
    channelMentionAutoFollowThreads: _string(
      json,
      'channel_mention_auto_follow_threads',
    ),
  );

  final String email;
  final String push;
  final String desktop;
  final String desktopSound;
  final String mentionKeys;
  final String channel;
  final String firstName;
  final String comments;
  final String desktopThreads;
  final String pushThreads;
  final String emailThreads;
  final String channelMentionAutoFollowThreads;
}

final class UserPropsDto {
  const UserPropsDto(this.values);

  factory UserPropsDto.fromJson(JsonMap json) =>
      UserPropsDto(_jsonValues(json));

  final Map<String, JsonValueDto> values;
}

final class MattermostTimezoneDto {
  const MattermostTimezoneDto({
    this.useAutomaticTimezone = false,
    this.manualTimezone = '',
    this.automaticTimezone = '',
  });

  factory MattermostTimezoneDto.fromJson(JsonMap json) => MattermostTimezoneDto(
    useAutomaticTimezone: _bool(json, 'useAutomaticTimezone'),
    manualTimezone: _string(json, 'manualTimezone'),
    automaticTimezone: _string(json, 'automaticTimezone'),
  );

  final bool useAutomaticTimezone;
  final String manualTimezone;
  final String automaticTimezone;
}

final class MattermostTeamDto {
  const MattermostTeamDto({
    required this.id,
    required this.name,
    required this.displayName,
    this.createAt = 0,
    this.updateAt = 0,
    this.deleteAt = 0,
    this.description = '',
    this.email = '',
    this.type = '',
    this.allowedDomains = '',
    this.inviteId = '',
    this.allowOpenInvite = false,
    this.policyId,
  });

  factory MattermostTeamDto.fromJson(JsonMap json) => MattermostTeamDto(
    id: _string(json, 'id'),
    name: _string(json, 'name'),
    displayName: _string(json, 'display_name'),
    createAt: _int(json, 'create_at'),
    updateAt: _int(json, 'update_at'),
    deleteAt: _int(json, 'delete_at'),
    description: _string(json, 'description'),
    email: _string(json, 'email'),
    type: _string(json, 'type'),
    allowedDomains: _string(json, 'allowed_domains'),
    inviteId: _string(json, 'invite_id'),
    allowOpenInvite: _bool(json, 'allow_open_invite'),
    policyId: _nullableString(json, 'policy_id'),
  );

  final String id;
  final int createAt;
  final int updateAt;
  final int deleteAt;
  final String displayName;
  final String name;
  final String description;
  final String email;
  final String type;
  final String allowedDomains;
  final String inviteId;
  final bool allowOpenInvite;
  final String? policyId;
}

final class MattermostChannelDto {
  const MattermostChannelDto({
    required this.id,
    required this.teamId,
    required this.type,
    required this.displayName,
    required this.name,
    this.createAt = 0,
    this.updateAt = 0,
    this.deleteAt = 0,
    this.header = '',
    this.purpose = '',
    this.lastPostAt = 0,
    this.totalMessageCount = 0,
    this.totalMessageCountRoot = 0,
    this.extraUpdateAt = 0,
    this.creatorId = '',
  });

  factory MattermostChannelDto.fromJson(JsonMap json) => MattermostChannelDto(
    id: _string(json, 'id'),
    createAt: _int(json, 'create_at'),
    updateAt: _int(json, 'update_at'),
    deleteAt: _int(json, 'delete_at'),
    teamId: _string(json, 'team_id'),
    type: _string(json, 'type'),
    displayName: _string(json, 'display_name'),
    name: _string(json, 'name'),
    header: _string(json, 'header'),
    purpose: _string(json, 'purpose'),
    lastPostAt: _int(json, 'last_post_at'),
    totalMessageCount: _int(json, 'total_msg_count'),
    totalMessageCountRoot: _int(json, 'total_msg_count_root'),
    extraUpdateAt: _int(json, 'extra_update_at'),
    creatorId: _string(json, 'creator_id'),
  );

  final String id;
  final int createAt;
  final int updateAt;
  final int deleteAt;
  final String teamId;
  final String type;
  final String displayName;
  final String name;
  final String header;
  final String purpose;
  final int lastPostAt;
  final int totalMessageCount;
  final int totalMessageCountRoot;
  final int extraUpdateAt;
  final String creatorId;
}

/// Aggregate counts returned by `GET /channels/{channel_id}/stats`.
final class MattermostChannelStatsDto {
  const MattermostChannelStatsDto({
    required this.channelId,
    this.memberCount = 0,
  });

  factory MattermostChannelStatsDto.fromJson(JsonMap json) =>
      MattermostChannelStatsDto(
        channelId: _string(json, 'channel_id'),
        memberCount: _int(json, 'member_count'),
      );

  final String channelId;
  final int memberCount;
}

/// Membership state returned by
/// `GET /users/{user_id}/teams/{team_id}/channels/members`.
final class MattermostChannelMemberDto {
  const MattermostChannelMemberDto({
    required this.channelId,
    required this.userId,
    this.roles = '',
    this.lastViewedAt = 0,
    this.msgCount = 0,
    this.msgCountRoot = 0,
    this.mentionCount = 0,
    this.mentionCountRoot = 0,
    this.urgentMentionCount = 0,
    this.notifyProps,
  });

  factory MattermostChannelMemberDto.fromJson(JsonMap json) =>
      MattermostChannelMemberDto(
        channelId: _string(json, 'channel_id'),
        userId: _string(json, 'user_id'),
        roles: _string(json, 'roles'),
        lastViewedAt: _int(json, 'last_viewed_at'),
        msgCount: _int(json, 'msg_count'),
        msgCountRoot: _int(json, 'msg_count_root'),
        mentionCount: _int(json, 'mention_count'),
        mentionCountRoot: _int(json, 'mention_count_root'),
        urgentMentionCount: _int(json, 'urgent_mention_count'),
        notifyProps: _nested(
          json,
          'notify_props',
          MattermostChannelNotifyPropsDto.fromJson,
        ),
      );

  final String channelId;
  final String userId;
  final String roles;
  final int lastViewedAt;
  final int msgCount;
  final int msgCountRoot;
  final int mentionCount;
  final int mentionCountRoot;
  final int urgentMentionCount;
  final MattermostChannelNotifyPropsDto? notifyProps;
}

/// Channel-scoped notification overrides carried by a channel membership.
final class MattermostChannelNotifyPropsDto {
  const MattermostChannelNotifyPropsDto({
    this.desktop = '',
    this.push = '',
    this.email = '',
    this.markUnread = '',
    this.ignoreChannelMentions = '',
    this.channelAutoFollowThreads = '',
  });

  factory MattermostChannelNotifyPropsDto.fromJson(JsonMap json) =>
      MattermostChannelNotifyPropsDto(
        desktop: _string(json, 'desktop'),
        push: _string(json, 'push'),
        email: _string(json, 'email'),
        markUnread: _string(json, 'mark_unread'),
        ignoreChannelMentions: _string(json, 'ignore_channel_mentions'),
        channelAutoFollowThreads: _string(json, 'channel_auto_follow_threads'),
      );

  final String desktop;
  final String push;
  final String email;
  final String markUnread;
  final String ignoreChannelMentions;
  final String channelAutoFollowThreads;
}

/// A single Mattermost user preference, usable for reads, upserts and deletes.
final class MattermostPreferenceDto {
  const MattermostPreferenceDto({
    required this.userId,
    required this.category,
    required this.name,
    required this.value,
  });

  factory MattermostPreferenceDto.fromJson(JsonMap json) =>
      MattermostPreferenceDto(
        userId: _string(json, 'user_id'),
        category: _string(json, 'category'),
        name: _string(json, 'name'),
        value: _string(json, 'value'),
      );

  final String userId;
  final String category;
  final String name;
  final String value;

  JsonMap toJson() => <String, Object?>{
    'user_id': userId,
    'category': category,
    'name': name,
    'value': value,
  };
}

/// Response from `/users/{user_id}/teams/{team_id}/channels/categories`.
final class MattermostChannelCategoriesDto {
  const MattermostChannelCategoriesDto({
    required this.categories,
    required this.order,
  });

  factory MattermostChannelCategoriesDto.fromJson(JsonMap json) =>
      MattermostChannelCategoriesDto(
        categories: _dtoList(
          json,
          'categories',
          MattermostChannelCategoryDto.fromJson,
        ),
        order: _stringList(json, 'order'),
      );

  final List<MattermostChannelCategoryDto> categories;
  final List<String> order;
}

/// Category item nested in [MattermostChannelCategoriesDto].
final class MattermostChannelCategoryDto {
  const MattermostChannelCategoryDto({
    required this.id,
    required this.userId,
    required this.teamId,
    required this.type,
    required this.displayName,
    required this.sorting,
    required this.channelIds,
    required this.muted,
    this.sortOrder = 0,
    this.collapsed = false,
  });

  factory MattermostChannelCategoryDto.fromJson(JsonMap json) =>
      MattermostChannelCategoryDto(
        id: _string(json, 'id'),
        userId: _string(json, 'user_id'),
        teamId: _string(json, 'team_id'),
        type: _string(json, 'type'),
        displayName: _string(json, 'display_name'),
        sorting: _string(json, 'sorting'),
        channelIds: _stringList(json, 'channel_ids'),
        muted: _bool(json, 'muted'),
        sortOrder: _int(json, 'sort_order'),
        collapsed: _bool(json, 'collapsed'),
      );

  final String id;
  final String userId;
  final String teamId;
  final String type;
  final String displayName;
  final String sorting;
  final List<String> channelIds;
  final bool muted;
  final int sortOrder;
  final bool collapsed;
}

/// Response from `POST /users/group_channels` keyed by channel ID.
final class MattermostGroupChannelUsersDto {
  const MattermostGroupChannelUsersDto({required this.usersByChannelId});

  final Map<String, List<MattermostUserDto>> usersByChannelId;
}

/// Aggregate response from the CRT followed-threads endpoint.
final class MattermostUserThreadsDto {
  const MattermostUserThreadsDto({
    required this.total,
    required this.totalUnreadThreads,
    required this.totalUnreadMentions,
    required this.threads,
  });

  factory MattermostUserThreadsDto.fromJson(JsonMap json) =>
      MattermostUserThreadsDto(
        total: _int(json, 'total'),
        totalUnreadThreads: _int(json, 'total_unread_threads'),
        totalUnreadMentions: _int(json, 'total_unread_mentions'),
        threads: _dtoList(json, 'threads', MattermostUserThreadDto.fromJson),
      );

  final int total;
  final int totalUnreadThreads;
  final int totalUnreadMentions;
  final List<MattermostUserThreadDto> threads;
}

final class MattermostUserThreadDto {
  const MattermostUserThreadDto({
    required this.id,
    required this.replyCount,
    required this.lastReplyAt,
    required this.lastViewedAt,
    required this.participants,
    required this.post,
    required this.unreadReplies,
    required this.unreadMentions,
    this.deleteAt = 0,
  });

  factory MattermostUserThreadDto.fromJson(JsonMap json) =>
      MattermostUserThreadDto(
        id: _string(json, 'id'),
        replyCount: _int(json, 'reply_count'),
        lastReplyAt: _int(json, 'last_reply_at'),
        lastViewedAt: _int(json, 'last_viewed_at'),
        participants: _dtoList(
          json,
          'participants',
          MattermostUserDto.fromJson,
        ),
        post: _nested(json, 'post', MattermostPostDto.fromJson),
        unreadReplies: _int(json, 'unread_replies'),
        unreadMentions: _int(json, 'unread_mentions'),
        deleteAt: _int(json, 'delete_at'),
      );

  final String id;
  final int replyCount;
  final int lastReplyAt;
  final int lastViewedAt;
  final List<MattermostUserDto> participants;
  final MattermostPostDto? post;
  final int unreadReplies;
  final int unreadMentions;
  final int deleteAt;
}

final class MattermostPostListDto {
  const MattermostPostListDto({
    required this.order,
    required this.posts,
    required this.nextPostId,
    required this.previousPostId,
    required this.hasNext,
  });

  factory MattermostPostListDto.fromJson(JsonMap json) => MattermostPostListDto(
    order: _stringList(json, 'order'),
    posts: _dtoMap(json, 'posts', MattermostPostDto.fromJson),
    nextPostId: _string(json, 'next_post_id'),
    previousPostId: _string(json, 'prev_post_id'),
    hasNext: _bool(json, 'has_next'),
  );

  final List<String> order;
  final Map<String, MattermostPostDto> posts;
  final String nextPostId;
  final String previousPostId;
  final bool hasNext;
}

/// Body accepted by `POST /api/v4/teams/{team_id}/posts/search`.
final class MattermostPostSearchRequestDto {
  const MattermostPostSearchRequestDto({
    required this.terms,
    required this.timezoneOffset,
    this.isOrSearch = false,
    this.includeDeletedChannels = false,
    this.page = 0,
    this.perPage = 60,
  });

  final String terms;
  final bool isOrSearch;
  final int timezoneOffset;
  final bool includeDeletedChannels;
  final int page;
  final int perPage;

  JsonMap toJson() => <String, Object?>{
    'terms': terms,
    'is_or_search': isOrSearch,
    'time_zone_offset': timezoneOffset,
    'include_deleted_channels': includeDeletedChannels,
    'page': page,
    'per_page': perPage,
  };
}

/// Tolerant response from the posts-search endpoint.
final class MattermostPostSearchDto {
  const MattermostPostSearchDto({
    required this.order,
    required this.posts,
    required this.matches,
  });

  factory MattermostPostSearchDto.fromJson(JsonMap json) =>
      MattermostPostSearchDto(
        order: _stringList(json, 'order'),
        posts: _dtoMap(json, 'posts', MattermostPostDto.fromJson),
        matches: _stringLists(json['matches']),
      );

  final List<String> order;
  final Map<String, MattermostPostDto> posts;
  final Map<String, List<String>> matches;
}

/// JSON body accepted by `POST /api/v4/posts`.
final class MattermostCreatePostRequestDto {
  const MattermostCreatePostRequestDto({
    required this.channelId,
    required this.message,
    required this.pendingPostId,
    this.rootId = '',
    this.fileIds = const <String>[],
  });

  final String channelId;
  final String message;
  final String pendingPostId;
  final String rootId;
  final List<String> fileIds;

  JsonMap toJson() => <String, Object?>{
    'channel_id': channelId,
    'message': message,
    'pending_post_id': pendingPostId,
    if (rootId.isNotEmpty) 'root_id': rootId,
    if (fileIds.isNotEmpty) 'file_ids': fileIds,
  };
}

/// Body for Mattermost's server-mediated legacy attachment action endpoint.
///
/// The cookie is opaque and optional for legacy actions. In particular,
/// integration configuration never crosses this DTO boundary.
final class MattermostPostActionRequestDto {
  const MattermostPostActionRequestDto({this.cookie, this.selectedOption});

  final String? cookie;
  final String? selectedOption;

  JsonMap toJson() => <String, Object?>{
    if (cookie case final String value when value.isNotEmpty) 'cookie': value,
    if (selectedOption case final String value) 'selected_option': value,
  };
}

/// Acknowledgement returned to the client after Mattermost dispatched an
/// interactive action. Post updates are deliberately fetched separately.
final class MattermostPostActionResponseDto {
  const MattermostPostActionResponseDto({
    required this.status,
    this.triggerId = '',
    this.gotoLocation = '',
  });

  factory MattermostPostActionResponseDto.fromJson(JsonMap json) =>
      MattermostPostActionResponseDto(
        status: _string(json, 'status'),
        triggerId: _string(json, 'trigger_id'),
        gotoLocation: _string(json, 'goto_location'),
      );

  final String status;
  final String triggerId;
  final String gotoLocation;
}

final class MattermostPostDto {
  const MattermostPostDto({
    required this.id,
    required this.userId,
    required this.channelId,
    required this.message,
    this.createAt = 0,
    this.updateAt = 0,
    this.deleteAt = 0,
    this.editAt = 0,
    this.rootId = '',
    this.replyCount = 0,
    this.lastReplyAt = 0,
    this.originalId = '',
    this.type = '',
    this.props,
    this.hashtag = '',
    this.fileIds = const <String>[],
    this.pendingPostId = '',
    this.metadata,
  });

  factory MattermostPostDto.fromJson(JsonMap json) => MattermostPostDto(
    id: _string(json, 'id'),
    createAt: _int(json, 'create_at'),
    updateAt: _int(json, 'update_at'),
    deleteAt: _int(json, 'delete_at'),
    editAt: _int(json, 'edit_at'),
    userId: _string(json, 'user_id'),
    channelId: _string(json, 'channel_id'),
    rootId: _string(json, 'root_id'),
    replyCount: _int(json, 'reply_count'),
    lastReplyAt: _int(json, 'last_reply_at'),
    originalId: _string(json, 'original_id'),
    message: _string(json, 'message'),
    type: _string(json, 'type'),
    props: _nested(json, 'props', MattermostPostPropsDto.fromJson),
    hashtag: _string(json, 'hashtag'),
    fileIds: _stringList(json, 'file_ids'),
    pendingPostId: _string(json, 'pending_post_id'),
    metadata: _nested(json, 'metadata', MattermostPostMetadataDto.fromJson),
  );

  final String id;
  final int createAt;
  final int updateAt;
  final int deleteAt;
  final int editAt;
  final String userId;
  final String channelId;
  final String rootId;
  final int replyCount;
  final int lastReplyAt;
  final String originalId;
  final String message;
  final String type;
  final MattermostPostPropsDto? props;
  final String hashtag;
  final List<String> fileIds;
  final String pendingPostId;
  final MattermostPostMetadataDto? metadata;
}

final class MattermostPostPropsDto {
  const MattermostPostPropsDto(this.values);

  factory MattermostPostPropsDto.fromJson(JsonMap json) =>
      MattermostPostPropsDto(_jsonValues(json));

  final Map<String, JsonValueDto> values;

  /// Legacy rich attachments carried in `post.props.attachments`.
  ///
  /// The lossless [values] map remains the protocol source. This projection is
  /// deliberately tolerant: a malformed attachment is omitted without making
  /// the containing post undecodable.
  List<MattermostLegacyAttachmentDto> get legacyAttachments => _jsonDtoList(
    values['attachments'],
    MattermostLegacyAttachmentDto.fromValues,
  );
}

final class MattermostLegacyAttachmentDto {
  const MattermostLegacyAttachmentDto({
    required this.rawProps,
    this.fallback = '',
    this.color = '',
    this.pretext = '',
    this.authorName = '',
    this.authorLink = '',
    this.authorIcon = '',
    this.title = '',
    this.titleLink = '',
    this.text = '',
    this.fields = const <MattermostLegacyAttachmentFieldDto>[],
    this.imageUrl = '',
    this.thumbUrl = '',
    this.footer = '',
    this.footerIcon = '',
    this.timestamp,
    this.actions = const <MattermostLegacyActionDto>[],
  });

  factory MattermostLegacyAttachmentDto.fromJson(JsonMap json) =>
      MattermostLegacyAttachmentDto.fromValues(_jsonValues(json));

  factory MattermostLegacyAttachmentDto.fromValues(
    Map<String, JsonValueDto> values,
  ) => MattermostLegacyAttachmentDto(
    rawProps: values,
    fallback: _jsonString(values, 'fallback'),
    color: _jsonString(values, 'color'),
    pretext: _jsonString(values, 'pretext'),
    authorName: _jsonString(values, 'author_name'),
    authorLink: _jsonString(values, 'author_link'),
    authorIcon: _jsonString(values, 'author_icon'),
    title: _jsonString(values, 'title'),
    titleLink: _jsonString(values, 'title_link'),
    text: _jsonString(values, 'text'),
    fields: _jsonDtoList(
      values['fields'],
      MattermostLegacyAttachmentFieldDto.fromValues,
    ),
    imageUrl: _jsonString(values, 'image_url'),
    thumbUrl: _jsonString(values, 'thumb_url'),
    footer: _jsonString(values, 'footer'),
    footerIcon: _jsonString(values, 'footer_icon'),
    timestamp: values['ts'],
    actions: _jsonDtoList(
      values['actions'],
      MattermostLegacyActionDto.fromValues,
    ),
  );

  final Map<String, JsonValueDto> rawProps;
  final String fallback;
  final String color;
  final String pretext;
  final String authorName;
  final String authorLink;
  final String authorIcon;
  final String title;
  final String titleLink;
  final String text;
  final List<MattermostLegacyAttachmentFieldDto> fields;
  final String imageUrl;
  final String thumbUrl;
  final String footer;
  final String footerIcon;
  final JsonValueDto? timestamp;
  final List<MattermostLegacyActionDto> actions;
}

final class MattermostLegacyAttachmentFieldDto {
  const MattermostLegacyAttachmentFieldDto({
    required this.rawProps,
    this.title = '',
    this.value = '',
    this.isShort = false,
  });

  factory MattermostLegacyAttachmentFieldDto.fromJson(JsonMap json) =>
      MattermostLegacyAttachmentFieldDto.fromValues(_jsonValues(json));

  factory MattermostLegacyAttachmentFieldDto.fromValues(
    Map<String, JsonValueDto> values,
  ) => MattermostLegacyAttachmentFieldDto(
    rawProps: values,
    title: _jsonString(values, 'title'),
    value: _jsonString(values, 'value'),
    isShort: _jsonBool(values, 'short'),
  );

  final Map<String, JsonValueDto> rawProps;
  final String title;
  final String value;
  final bool isShort;
}

sealed class MattermostLegacyActionDto {
  const MattermostLegacyActionDto({
    required this.id,
    required this.name,
    required this.type,
    required this.rawProps,
    this.cookie,
  });

  factory MattermostLegacyActionDto.fromJson(JsonMap json) =>
      MattermostLegacyActionDto.fromValues(_jsonValues(json));

  factory MattermostLegacyActionDto.fromValues(
    Map<String, JsonValueDto> values,
  ) {
    final String type = _jsonString(values, 'type');
    final String id = _jsonString(values, 'id');
    final String name = _jsonString(values, 'name');
    final String? cookie = _jsonNullableString(values, 'cookie');
    final Map<String, JsonValueDto> publicRawProps = _withoutPrivateActionProps(
      values,
    );

    return switch (type) {
      'button' => MattermostLegacyButtonActionDto(
        id: id,
        name: name,
        rawProps: publicRawProps,
        cookie: cookie,
        tooltip: _jsonString(values, 'tooltip'),
        style: _jsonString(values, 'style'),
      ),
      'select' => MattermostLegacySelectActionDto(
        id: id,
        name: name,
        rawProps: publicRawProps,
        cookie: cookie,
        dataSource: _jsonString(values, 'data_source'),
        options: _jsonDtoList(
          values['options'],
          MattermostLegacyActionOptionDto.fromValues,
        ),
        defaultOption: _jsonNullableString(values, 'default_option'),
      ),
      _ => MattermostLegacyUnknownActionDto(
        id: id,
        name: name,
        type: type,
        rawProps: publicRawProps,
        cookie: cookie,
      ),
    };
  }

  final String id;
  final String name;
  final String type;

  /// Opaque token which must only be passed through to the domain layer.
  final String? cookie;

  /// Lossless public action properties, excluding `integration` and `context`.
  final Map<String, JsonValueDto> rawProps;
}

final class MattermostLegacyButtonActionDto extends MattermostLegacyActionDto {
  const MattermostLegacyButtonActionDto({
    required super.id,
    required super.name,
    required super.rawProps,
    super.cookie,
    this.tooltip = '',
    this.style = '',
  }) : super(type: 'button');

  final String tooltip;
  final String style;
}

final class MattermostLegacySelectActionDto extends MattermostLegacyActionDto {
  const MattermostLegacySelectActionDto({
    required super.id,
    required super.name,
    required super.rawProps,
    super.cookie,
    this.dataSource = '',
    this.options = const <MattermostLegacyActionOptionDto>[],
    this.defaultOption,
  }) : super(type: 'select');

  final String dataSource;
  final List<MattermostLegacyActionOptionDto> options;
  final String? defaultOption;
}

final class MattermostLegacyUnknownActionDto extends MattermostLegacyActionDto {
  const MattermostLegacyUnknownActionDto({
    required super.id,
    required super.name,
    required super.type,
    required super.rawProps,
    super.cookie,
  });
}

final class MattermostLegacyActionOptionDto {
  const MattermostLegacyActionOptionDto({
    required this.rawProps,
    this.text = '',
    this.value = '',
  });

  factory MattermostLegacyActionOptionDto.fromJson(JsonMap json) =>
      MattermostLegacyActionOptionDto.fromValues(_jsonValues(json));

  factory MattermostLegacyActionOptionDto.fromValues(
    Map<String, JsonValueDto> values,
  ) => MattermostLegacyActionOptionDto(
    rawProps: values,
    text: _jsonString(values, 'text'),
    value: _jsonString(values, 'value'),
  );

  final Map<String, JsonValueDto> rawProps;
  final String text;
  final String value;
}

final class MattermostPostMetadataDto {
  const MattermostPostMetadataDto({
    this.embeds = const <MattermostPostEmbedDto>[],
    this.emojis = const <MattermostEmojiDto>[],
    this.files = const <MattermostFileInfoDto>[],
    this.images = const <String, MattermostImageDimensionsDto>{},
    this.reactions = const <MattermostReactionDto>[],
    this.priority,
    this.acknowledgements = const <MattermostPostAcknowledgementDto>[],
  });

  factory MattermostPostMetadataDto.fromJson(JsonMap json) =>
      MattermostPostMetadataDto(
        embeds: _dtoList(json, 'embeds', MattermostPostEmbedDto.fromJson),
        emojis: _dtoList(json, 'emojis', MattermostEmojiDto.fromJson),
        files: _dtoList(json, 'files', MattermostFileInfoDto.fromJson),
        images: _dtoMap(json, 'images', MattermostImageDimensionsDto.fromJson),
        reactions: _dtoList(json, 'reactions', MattermostReactionDto.fromJson),
        priority: _nested(json, 'priority', MattermostPostPriorityDto.fromJson),
        acknowledgements: _dtoList(
          json,
          'acknowledgements',
          MattermostPostAcknowledgementDto.fromJson,
        ),
      );

  final List<MattermostPostEmbedDto> embeds;
  final List<MattermostEmojiDto> emojis;
  final List<MattermostFileInfoDto> files;
  final Map<String, MattermostImageDimensionsDto> images;
  final List<MattermostReactionDto> reactions;
  final MattermostPostPriorityDto? priority;
  final List<MattermostPostAcknowledgementDto> acknowledgements;
}

final class MattermostPostEmbedDto {
  const MattermostPostEmbedDto({
    required this.type,
    required this.url,
    this.data,
  });

  factory MattermostPostEmbedDto.fromJson(JsonMap json) =>
      MattermostPostEmbedDto(
        type: _string(json, 'type'),
        url: _string(json, 'url'),
        data: _nested(json, 'data', MattermostPostEmbedDataDto.fromJson),
      );

  final String type;
  final String url;
  final MattermostPostEmbedDataDto? data;
}

final class MattermostPostEmbedDataDto {
  const MattermostPostEmbedDataDto(this.values);

  factory MattermostPostEmbedDataDto.fromJson(JsonMap json) =>
      MattermostPostEmbedDataDto(_jsonValues(json));

  final Map<String, JsonValueDto> values;
}

final class MattermostImageDimensionsDto {
  const MattermostImageDimensionsDto({
    required this.height,
    required this.width,
  });

  factory MattermostImageDimensionsDto.fromJson(JsonMap json) =>
      MattermostImageDimensionsDto(
        height: _int(json, 'height'),
        width: _int(json, 'width'),
      );

  final int height;
  final int width;
}

final class MattermostPostPriorityDto {
  const MattermostPostPriorityDto({
    required this.priority,
    required this.requestedAcknowledgement,
  });

  factory MattermostPostPriorityDto.fromJson(JsonMap json) =>
      MattermostPostPriorityDto(
        priority: _string(json, 'priority'),
        requestedAcknowledgement: _bool(json, 'requested_ack'),
      );

  final String priority;
  final bool requestedAcknowledgement;
}

final class MattermostReactionDto {
  const MattermostReactionDto({
    required this.userId,
    required this.postId,
    required this.emojiName,
    required this.createAt,
  });

  factory MattermostReactionDto.fromJson(JsonMap json) => MattermostReactionDto(
    userId: _string(json, 'user_id'),
    postId: _string(json, 'post_id'),
    emojiName: _string(json, 'emoji_name'),
    createAt: _int(json, 'create_at'),
  );

  final String userId;
  final String postId;
  final String emojiName;
  final int createAt;
}

final class MattermostPostAcknowledgementDto {
  const MattermostPostAcknowledgementDto({
    required this.userId,
    required this.postId,
    required this.acknowledgedAt,
  });

  factory MattermostPostAcknowledgementDto.fromJson(JsonMap json) =>
      MattermostPostAcknowledgementDto(
        userId: _string(json, 'user_id'),
        postId: _string(json, 'post_id'),
        acknowledgedAt: _int(json, 'acknowledged_at'),
      );

  final String userId;
  final String postId;
  final int acknowledgedAt;
}

final class MattermostEmojiDto {
  const MattermostEmojiDto({
    required this.id,
    required this.creatorId,
    required this.name,
    required this.createAt,
    required this.updateAt,
    required this.deleteAt,
  });

  factory MattermostEmojiDto.fromJson(JsonMap json) => MattermostEmojiDto(
    id: _string(json, 'id'),
    creatorId: _string(json, 'creator_id'),
    name: _string(json, 'name'),
    createAt: _int(json, 'create_at'),
    updateAt: _int(json, 'update_at'),
    deleteAt: _int(json, 'delete_at'),
  );

  final String id;
  final String creatorId;
  final String name;
  final int createAt;
  final int updateAt;
  final int deleteAt;
}

final class MattermostFileInfoDto {
  const MattermostFileInfoDto({
    required this.id,
    required this.userId,
    required this.postId,
    required this.createAt,
    required this.updateAt,
    required this.deleteAt,
    required this.name,
    required this.extension,
    required this.size,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.hasPreviewImage,
    required this.miniPreview,
    required this.content,
    required this.remoteId,
    required this.archived,
  });

  factory MattermostFileInfoDto.fromJson(JsonMap json) => MattermostFileInfoDto(
    id: _string(json, 'id'),
    userId: _string(json, 'user_id'),
    postId: _string(json, 'post_id'),
    createAt: _int(json, 'create_at'),
    updateAt: _int(json, 'update_at'),
    deleteAt: _int(json, 'delete_at'),
    name: _string(json, 'name'),
    extension: _string(json, 'extension'),
    size: _int(json, 'size'),
    mimeType: _string(json, 'mime_type'),
    width: _int(json, 'width'),
    height: _int(json, 'height'),
    hasPreviewImage: _bool(json, 'has_preview_image'),
    miniPreview: _nullableString(json, 'mini_preview'),
    content: _string(json, 'content'),
    remoteId: _string(json, 'remote_id'),
    archived: _bool(json, 'archived'),
  );

  final String id;
  final String userId;
  final String postId;
  final int createAt;
  final int updateAt;
  final int deleteAt;
  final String name;
  final String extension;
  final int size;
  final String mimeType;
  final int width;
  final int height;
  final bool hasPreviewImage;
  final String? miniPreview;
  final String content;
  final String remoteId;
  final bool archived;
}

sealed class JsonValueDto {
  const JsonValueDto();

  factory JsonValueDto.fromJson(Object? value) => switch (value) {
    null => const JsonNullDto(),
    final bool value => JsonBooleanDto(value),
    final num value => JsonNumberDto(value),
    final String value => JsonStringDto(value),
    final List<Object?> value => JsonArrayDto(
      value.map(JsonValueDto.fromJson).toList(growable: false),
    ),
    final Map<String, Object?> value => JsonObjectDto(_jsonValues(value)),
    _ => throw const FormatException('Unsupported JSON value'),
  };
}

final class JsonNullDto extends JsonValueDto {
  const JsonNullDto();
}

final class JsonBooleanDto extends JsonValueDto {
  const JsonBooleanDto(this.value);

  final bool value;
}

final class JsonNumberDto extends JsonValueDto {
  const JsonNumberDto(this.value);

  final num value;
}

final class JsonStringDto extends JsonValueDto {
  const JsonStringDto(this.value);

  final String value;
}

final class JsonArrayDto extends JsonValueDto {
  const JsonArrayDto(this.values);

  final List<JsonValueDto> values;
}

final class JsonObjectDto extends JsonValueDto {
  const JsonObjectDto(this.values);

  final Map<String, JsonValueDto> values;
}

String _string(JsonMap json, String key) {
  final Object? value = json[key];
  if (value == null) return '';
  if (value is String) return value;
  throw FormatException('Expected string at $key');
}

String? _nullableString(JsonMap json, String key) {
  final Object? value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('Expected nullable string at $key');
}

int _int(JsonMap json, String key) {
  final Object? value = json[key];
  if (value == null) return 0;
  if (value is int) return value;
  throw FormatException('Expected integer at $key');
}

bool _bool(JsonMap json, String key) {
  final Object? value = json[key];
  if (value == null) return false;
  if (value is bool) return value;
  if (value is String) {
    if (value.toLowerCase() == "true") {
      return true;
    } else if (value.toLowerCase() == "false") {
      return false;
    }
  }
  throw FormatException('Expected boolean at $key');
}

List<String> _stringList(JsonMap json, String key) {
  final Object? value = json[key];
  if (value == null) return const <String>[];
  if (value is! List<Object?> || value.any((Object? item) => item is! String)) {
    throw FormatException('Expected string array at $key');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

T? _nested<T>(JsonMap json, String key, T Function(JsonMap) decode) {
  final Object? value = json[key];
  if (value == null) return null;
  if (value is! JsonMap) throw FormatException('Expected object at $key');
  return decode(value);
}

List<T> _dtoList<T>(JsonMap json, String key, T Function(JsonMap) decode) {
  final Object? value = json[key];
  if (value == null) return const <Never>[];
  if (value is! List<Object?>) throw FormatException('Expected array at $key');
  return List<T>.unmodifiable(
    value.map((Object? item) {
      if (item is! JsonMap) throw FormatException('Expected object in $key');
      return decode(item);
    }),
  );
}

Map<String, T> _dtoMap<T>(
  JsonMap json,
  String key,
  T Function(JsonMap) decode,
) {
  final Object? value = json[key];
  if (value == null) return const <String, Never>{};
  if (value is! JsonMap) throw FormatException('Expected object map at $key');
  return Map<String, T>.unmodifiable(
    value.map((String id, Object? item) {
      if (item is! JsonMap) {
        throw FormatException('Expected object at $key.$id');
      }
      return MapEntry<String, T>(id, decode(item));
    }),
  );
}

Map<String, List<String>> _stringLists(Object? value) {
  if (value is! JsonMap) return const <String, List<String>>{};
  final Map<String, List<String>> result = <String, List<String>>{};
  for (final MapEntry<String, Object?> entry in value.entries) {
    if (entry.value is! List<Object?>) continue;
    final List<Object?> values = entry.value! as List<Object?>;
    result[entry.key] = List<String>.unmodifiable(values.whereType<String>());
  }
  return Map<String, List<String>>.unmodifiable(result);
}

Map<String, JsonValueDto> _jsonValues(JsonMap json) =>
    Map<String, JsonValueDto>.unmodifiable(
      json.map(
        (String key, Object? value) =>
            MapEntry<String, JsonValueDto>(key, JsonValueDto.fromJson(value)),
      ),
    );

String _jsonString(Map<String, JsonValueDto> values, String key) {
  final JsonValueDto? value = values[key];
  if (value == null || value is JsonNullDto) return '';
  if (value case JsonStringDto(:final String value)) return value;
  throw FormatException('Expected string at $key');
}

String? _jsonNullableString(Map<String, JsonValueDto> values, String key) {
  final JsonValueDto? value = values[key];
  if (value == null || value is JsonNullDto) return null;
  if (value case JsonStringDto(:final String value)) return value;
  throw FormatException('Expected nullable string at $key');
}

bool _jsonBool(Map<String, JsonValueDto> values, String key) {
  final JsonValueDto? value = values[key];
  if (value == null || value is JsonNullDto) return false;
  if (value case JsonBooleanDto(:final bool value)) return value;
  if (value case JsonStringDto(value: final String value)) {
    if (value.toLowerCase() == 'true') return true;
    if (value.toLowerCase() == 'false') return false;
  }
  throw FormatException('Expected boolean at $key');
}

List<T> _jsonDtoList<T>(
  JsonValueDto? value,
  T Function(Map<String, JsonValueDto>) decode,
) {
  if (value == null || value is JsonNullDto) return const <Never>[];
  if (value is! JsonArrayDto) return const <Never>[];

  final List<T> result = <T>[];
  for (final JsonValueDto item in value.values) {
    if (item is! JsonObjectDto) continue;
    try {
      result.add(decode(item.values));
    } on FormatException {
      // A malformed child must not make its parent object undecodable.
    }
  }
  return List<T>.unmodifiable(result);
}

Map<String, JsonValueDto> _withoutPrivateActionProps(
  Map<String, JsonValueDto> values,
) => Map<String, JsonValueDto>.unmodifiable(
  Map<String, JsonValueDto>.from(values)
    ..remove('integration')
    ..remove('context'),
);
