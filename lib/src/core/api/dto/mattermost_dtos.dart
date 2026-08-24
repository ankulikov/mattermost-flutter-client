/// Wire DTOs for the Mattermost API v4 endpoints exposed by [MattermostApi].
///
/// These types deliberately stay in the API layer. Domain entities and database
/// rows must be produced by explicit mappers.
library;

typedef JsonMap = Map<String, Object?>;

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
    this.email = '',
    this.emailVerified = false,
    this.authService = '',
    this.roles = '',
    this.locale = '',
    this.notifyProps,
    this.props,
    this.lastPasswordUpdate = 0,
    this.lastPictureUpdate = 0,
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
    email: _string(json, 'email'),
    emailVerified: _bool(json, 'email_verified'),
    authService: _string(json, 'auth_service'),
    roles: _string(json, 'roles'),
    locale: _string(json, 'locale'),
    notifyProps: _nested(json, 'notify_props', UserNotifyPropsDto.fromJson),
    props: _nested(json, 'props', UserPropsDto.fromJson),
    lastPasswordUpdate: _int(json, 'last_password_update'),
    lastPictureUpdate: _int(json, 'last_picture_update'),
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
  final String email;
  final bool emailVerified;
  final String authService;
  final String roles;
  final String locale;
  final UserNotifyPropsDto? notifyProps;
  final UserPropsDto? props;
  final int lastPasswordUpdate;
  final int lastPictureUpdate;
  final int failedAttempts;
  final bool mfaActive;
  final MattermostTimezoneDto? timezone;
  final String? termsOfServiceId;
  final int termsOfServiceCreateAt;
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
  final int extraUpdateAt;
  final String creatorId;
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

Map<String, JsonValueDto> _jsonValues(JsonMap json) =>
    Map<String, JsonValueDto>.unmodifiable(
      json.map(
        (String key, Object? value) =>
            MapEntry<String, JsonValueDto>(key, JsonValueDto.fromJson(value)),
      ),
    );
