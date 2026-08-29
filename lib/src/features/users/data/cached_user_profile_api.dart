import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/users/data/user_profile_cache.dart';

/// Adds tenant-scoped, DB-first caching only to user detail lookups by ID.
/// Profile images and every other REST operation are delegated unchanged.
final class CachedUserProfileApi implements MattermostApi {
  CachedUserProfileApi({
    required MattermostApi delegate,
    required UserProfileCache cache,
    required String accountId,
    DateTime Function()? now,
  }) : _delegate = delegate,
       _cache = cache,
       _accountId = accountId,
       _now = now ?? DateTime.now;

  static const Duration cacheLifetime = Duration(days: 7);

  final MattermostApi _delegate;
  final UserProfileCache _cache;
  final String _accountId;
  final DateTime Function() _now;

  @override
  Future<List<MattermostUserDto>> getUsersByIds(List<String> userIds) async {
    final List<String> requestedIds = userIds
        .where((String id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (requestedIds.isEmpty) return const <MattermostUserDto>[];

    final DateTime checkedAt = _now().toUtc();
    final List<CachedUserProfile> cached = await _cache.getByIds(
      accountId: _accountId,
      userIds: requestedIds,
    );
    final Map<String, MattermostUserDto> usersById =
        <String, MattermostUserDto>{
          for (final CachedUserProfile profile in cached)
            if (profile.expiresAt.toUtc().isAfter(checkedAt))
              profile.userId: _fromCache(profile),
        };
    final List<String> staleOrMissingIds = requestedIds
        .where((String id) => !usersById.containsKey(id))
        .toList(growable: false);

    if (staleOrMissingIds.isNotEmpty) {
      final List<MattermostUserDto> loaded = await _delegate.getUsersByIds(
        staleOrMissingIds,
      );
      final DateTime expiresAt = _now().toUtc().add(cacheLifetime);
      final List<MattermostUserDto> validLoaded = loaded
          .where(
            (MattermostUserDto user) =>
                user.id.isNotEmpty && staleOrMissingIds.contains(user.id),
          )
          .toList(growable: false);
      await _cache.upsertAll(
        accountId: _accountId,
        profiles: validLoaded
            .map(
              (MattermostUserDto user) => CachedUserProfile(
                userId: user.id,
                firstName: user.firstName,
                lastName: user.lastName,
                username: user.username,
                nickname: user.nickname,
                position: user.position,
                email: user.email,
                profileImageUpdatedAt: user.profileImageUpdatedAt,
                expiresAt: expiresAt,
              ),
            )
            .toList(growable: false),
      );
      usersById.addEntries(
        validLoaded.map(
          (MattermostUserDto user) =>
              MapEntry<String, MattermostUserDto>(user.id, user),
        ),
      );
    }

    return requestedIds
        .map((String id) => usersById[id])
        .whereType<MattermostUserDto>()
        .toList(growable: false);
  }

  @override
  Future<List<MattermostUserDto>> getUsersByUsernames(
    List<String> usernames,
  ) async {
    final List<String> requested = usernames
        .where((String username) => username.isNotEmpty)
        .map((String username) => username.toLowerCase())
        .toSet()
        .toList(growable: false);
    if (requested.isEmpty) return const <MattermostUserDto>[];

    final DateTime checkedAt = _now().toUtc();
    final List<CachedUserProfile> cached = await _cache.getByUsernames(
      accountId: _accountId,
      usernames: requested,
    );
    final Map<String, MattermostUserDto> usersByUsername =
        <String, MattermostUserDto>{
          for (final CachedUserProfile profile in cached)
            if (profile.expiresAt.toUtc().isAfter(checkedAt))
              profile.username.toLowerCase(): _fromCache(profile),
        };

    final List<CachedUserProfile> stale = cached
        .where(
          (CachedUserProfile profile) =>
              !profile.expiresAt.toUtc().isAfter(checkedAt),
        )
        .toList(growable: false);
    final Set<String> staleIds = stale
        .map((CachedUserProfile profile) => profile.userId)
        .toSet();
    final List<MattermostUserDto> refreshedResponse = stale.isEmpty
        ? const <MattermostUserDto>[]
        : await _delegate.getUsersByIds(staleIds.toList(growable: false));
    final List<MattermostUserDto> refreshed = refreshedResponse
        .where((MattermostUserDto user) => staleIds.contains(user.id))
        .toList(growable: false);
    usersByUsername.addEntries(
      refreshed.map(
        (MattermostUserDto user) => MapEntry<String, MattermostUserDto>(
          user.username.toLowerCase(),
          user,
        ),
      ),
    );

    final Set<String> knownCachedNames = cached
        .map((CachedUserProfile profile) => profile.username.toLowerCase())
        .toSet();
    final List<String> missingNames = requested
        .where((String username) => !knownCachedNames.contains(username))
        .toList(growable: false);
    final List<MattermostUserDto> loadedResponse = missingNames.isEmpty
        ? const <MattermostUserDto>[]
        : await _delegate.getUsersByUsernames(missingNames);
    final Set<String> missingNameSet = missingNames.toSet();
    final List<MattermostUserDto> loaded = loadedResponse
        .where(
          (MattermostUserDto user) =>
              user.id.isNotEmpty &&
              missingNameSet.contains(user.username.toLowerCase()),
        )
        .toList(growable: false);
    usersByUsername.addEntries(
      loaded.map(
        (MattermostUserDto user) => MapEntry<String, MattermostUserDto>(
          user.username.toLowerCase(),
          user,
        ),
      ),
    );

    await _cacheUsers(<MattermostUserDto>[...refreshed, ...loaded]);
    return requested
        .map((String username) => usersByUsername[username])
        .whereType<MattermostUserDto>()
        .toList(growable: false);
  }

  Future<void> _cacheUsers(List<MattermostUserDto> users) async {
    if (users.isEmpty) return;
    final DateTime expiresAt = _now().toUtc().add(cacheLifetime);
    await _cache.upsertAll(
      accountId: _accountId,
      profiles: users
          .where((MattermostUserDto user) => user.id.isNotEmpty)
          .map(
            (MattermostUserDto user) => CachedUserProfile(
              userId: user.id,
              firstName: user.firstName,
              lastName: user.lastName,
              username: user.username,
              nickname: user.nickname,
              position: user.position,
              email: user.email,
              profileImageUpdatedAt: user.profileImageUpdatedAt,
              expiresAt: expiresAt,
            ),
          )
          .toList(growable: false),
    );
  }

  static MattermostUserDto _fromCache(CachedUserProfile profile) =>
      MattermostUserDto(
        id: profile.userId,
        username: profile.username,
        firstName: profile.firstName,
        lastName: profile.lastName,
        nickname: profile.nickname,
        position: profile.position,
        email: profile.email,
        lastPictureUpdate: profile.profileImageUpdatedAt,
      );

  @override
  Future<MattermostUserDto> getUserById(String userId) =>
      _delegate.getUserById(userId);

  @override
  Future<MattermostUserStatusDto> getUserStatus(String userId) =>
      _delegate.getUserStatus(userId);

  @override
  Future<MattermostUserDto> getCurrentUser() => _delegate.getCurrentUser();

  @override
  Future<List<MattermostTeamDto>> getTeamsForCurrentUser() =>
      _delegate.getTeamsForCurrentUser();

  @override
  Future<List<MattermostChannelDto>> getChannelsForUser({
    required String userId,
    required String teamId,
    String? etag,
  }) =>
      _delegate.getChannelsForUser(userId: userId, teamId: teamId, etag: etag);

  @override
  Future<MattermostChannelCategoriesDto> getChannelCategories({
    required String userId,
    required String teamId,
  }) => _delegate.getChannelCategories(userId: userId, teamId: teamId);

  @override
  Future<MattermostImageDto> getUserProfileImage({
    required String userId,
    int lastPictureUpdate = 0,
  }) => _delegate.getUserProfileImage(
    userId: userId,
    lastPictureUpdate: lastPictureUpdate,
  );

  @override
  Future<MattermostEmojiDto> getCustomEmojiByName(String name) =>
      _delegate.getCustomEmojiByName(name);

  @override
  Future<MattermostImageDto> getCustomEmojiImage(String emojiId) =>
      _delegate.getCustomEmojiImage(emojiId);

  @override
  Future<MattermostFileContentDto> getFile(String fileId) =>
      _delegate.getFile(fileId);

  @override
  Future<MattermostFileContentDto> getFileThumbnail(String fileId) =>
      _delegate.getFileThumbnail(fileId);

  @override
  Future<MattermostFileContentDto> getFilePreview(String fileId) =>
      _delegate.getFilePreview(fileId);

  @override
  Future<MattermostGroupChannelUsersDto> getUsersForGroupChannels(
    List<String> channelIds,
  ) => _delegate.getUsersForGroupChannels(channelIds);

  @override
  Future<MattermostChannelDto> createDirectChannel({
    required String currentUserId,
    required String otherUserId,
  }) => _delegate.createDirectChannel(
    currentUserId: currentUserId,
    otherUserId: otherUserId,
  );

  @override
  Future<MattermostPostListDto> getPostsForChannel({
    required String channelId,
    int page = 0,
    int perPage = 60,
    String? etag,
  }) => _delegate.getPostsForChannel(
    channelId: channelId,
    page: page,
    perPage: perPage,
    etag: etag,
  );

  @override
  Future<MattermostPostListDto> getPostsBefore({
    required String channelId,
    required String postId,
    int page = 0,
    int perPage = 60,
  }) => _delegate.getPostsBefore(
    channelId: channelId,
    postId: postId,
    page: page,
    perPage: perPage,
  );

  @override
  Future<MattermostPostListDto> getPostsSince({
    required String channelId,
    required int since,
  }) => _delegate.getPostsSince(channelId: channelId, since: since);

  @override
  Future<MattermostPostDto> createPost(MattermostCreatePostRequestDto post) =>
      _delegate.createPost(post);

  @override
  Future<void> saveReaction({
    required String userId,
    required String postId,
    required String emojiName,
  }) => _delegate.saveReaction(
    userId: userId,
    postId: postId,
    emojiName: emojiName,
  );

  @override
  Future<void> deleteReaction({
    required String userId,
    required String postId,
    required String emojiName,
  }) => _delegate.deleteReaction(
    userId: userId,
    postId: postId,
    emojiName: emojiName,
  );

  @override
  Future<MattermostPostListDto> getPostThread({
    required String rootPostId,
    int perPage = 60,
    String? fromPost,
    int? fromCreateAt,
    PostThreadDirection direction = PostThreadDirection.up,
  }) => _delegate.getPostThread(
    rootPostId: rootPostId,
    perPage: perPage,
    fromPost: fromPost,
    fromCreateAt: fromCreateAt,
    direction: direction,
  );

  @override
  Future<MattermostUserThreadsDto> getUserThreads({
    required String userId,
    required String teamId,
    int perPage = 60,
    String? before,
    bool extended = true,
    bool unread = false,
  }) => _delegate.getUserThreads(
    userId: userId,
    teamId: teamId,
    perPage: perPage,
    before: before,
    extended: extended,
    unread: unread,
  );

  @override
  Future<void> updateThreadRead({
    required String userId,
    required String teamId,
    required String threadId,
    required int timestamp,
  }) => _delegate.updateThreadRead(
    userId: userId,
    teamId: teamId,
    threadId: threadId,
    timestamp: timestamp,
  );
}
