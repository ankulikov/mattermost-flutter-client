import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';

enum PostThreadDirection { up, down }

/// Boundary of the Mattermost REST API.
///
/// Feature and domain code depend on this contract, never on Dio or HTTP.
abstract interface class MattermostApi {
  Future<MattermostUserDto> getCurrentUser();

  Future<List<MattermostTeamDto>> getTeamsForCurrentUser();

  Future<List<MattermostChannelDto>> getChannelsForUser({
    required String userId,
    required String teamId,
    String? etag,
  });

  Future<MattermostChannelDto> getChannel(String channelId) =>
      throw UnimplementedError();

  Future<MattermostChannelCategoriesDto> getChannelCategories({
    required String userId,
    required String teamId,
  });

  /// Returns the current user's membership counters and notification settings
  /// for every channel in [teamId].
  Future<List<MattermostChannelMemberDto>> getChannelMembersForUser({
    required String userId,
    required String teamId,
  });

  Future<List<MattermostUserDto>> getUsersByIds(List<String> userIds);

  /// Returns users matching the supplied exact usernames.
  Future<List<MattermostUserDto>> getUsersByUsernames(List<String> usernames);

  /// Returns people eligible for a channel mention, grouped by channel
  /// membership by the server.
  Future<MattermostUserAutocompleteDto> autocompleteUsers({
    required String teamId,
    required String channelId,
    required String name,
    required int limit,
  }) => throw UnimplementedError();

  /// Searches groups which the server permits using as at-mentions.
  Future<List<MattermostGroupDto>> searchMentionGroups({
    required String name,
    required int limit,
  }) => throw UnimplementedError();

  /// Resolves exact group at-mention handles in one request.
  Future<List<MattermostGroupDto>> getGroupsByNames(List<String> names) =>
      throw UnimplementedError();

  /// Returns a fresh user projection without the batch profile cache.
  Future<MattermostUserDto> getUserById(String userId);

  Future<MattermostUserStatusDto> getUserStatus(String userId);

  /// Returns the authenticated user's view of [userId]'s profile image.
  ///
  /// Mattermost ignores [lastPictureUpdate] on the server; it exists solely to
  /// version client and intermediary cache keys.
  Future<MattermostImageDto> getUserProfileImage({
    required String userId,
    int lastPictureUpdate = 0,
  });

  /// Resolves custom emoji metadata by its exact shortcode name.
  Future<MattermostEmojiDto> getCustomEmojiByName(String name);

  /// Returns a name-sorted page of custom emoji metadata.
  Future<List<MattermostEmojiDto>> getCustomEmojis({
    int page = 0,
    int perPage = 90,
  });

  /// Searches custom emoji names. The server returns at most 200 entries.
  Future<List<MattermostEmojiDto>> searchCustomEmojis(String term);

  /// Returns the authenticated user's view of a custom emoji image.
  Future<MattermostImageDto> getCustomEmojiImage(String emojiId);

  /// Returns an authenticated original file attachment.
  Future<MattermostFileContentDto> getFile(String fileId);

  /// Returns an authenticated, small image representation for a file.
  Future<MattermostFileContentDto> getFileThumbnail(String fileId);

  /// Returns an authenticated, screen-sized image representation for a file.
  Future<MattermostFileContentDto> getFilePreview(String fileId);

  Future<MattermostGroupChannelUsersDto> getUsersForGroupChannels(
    List<String> channelIds,
  );

  Future<MattermostChannelDto> createDirectChannel({
    required String currentUserId,
    required String otherUserId,
  });

  Future<MattermostPostListDto> getPostsForChannel({
    required String channelId,
    int page = 0,
    int perPage = 60,
    String? etag,
  });

  Future<MattermostPostListDto> getPostsBefore({
    required String channelId,
    required String postId,
    int page = 0,
    int perPage = 60,
  });

  Future<MattermostPostListDto> getPostsAfter({
    required String channelId,
    required String postId,
    int page = 0,
    int perPage = 60,
  }) => throw UnimplementedError();

  Future<MattermostPostDto> getPost(String postId) =>
      throw UnimplementedError();

  /// Returns posts modified after [since] (Unix milliseconds). Mattermost may
  /// return up to 1000 non-consecutive posts, so callers must reconcile holes.
  Future<MattermostPostListDto> getPostsSince({
    required String channelId,
    required int since,
  });

  /// Returns posts around the oldest unread post in a channel. The response is
  /// bounded by [limitBefore] and [limitAfter] on the respective sides.
  Future<MattermostPostListDto> getUnreadPostsForChannel({
    required String userId,
    required String channelId,
    int limitBefore = 0,
    int limitAfter = 200,
  });

  /// Hydrates posts referenced by IDs, including postponed Inbox entries.
  Future<List<MattermostPostDto>> getPostsByIds(List<String> postIds);

  /// Creates a channel post or a threaded reply through the REST API.
  Future<MattermostPostDto> createPost(MattermostCreatePostRequestDto post);

  /// Adds the authenticated user's emoji reaction to a post.
  Future<void> saveReaction({
    required String userId,
    required String postId,
    required String emojiName,
  });

  /// Removes the authenticated user's emoji reaction from a post.
  Future<void> deleteReaction({
    required String userId,
    required String postId,
    required String emojiName,
  });

  /// Returns the root and posts belonging to its thread. Responses may be
  /// paginated; [fromPost] and [fromCreateAt] resume from the last item while
  /// [direction] selects older (`up`) or newer (`down`) replies.
  Future<MattermostPostListDto> getPostThread({
    required String rootPostId,
    int perPage = 60,
    String? fromPost,
    int? fromCreateAt,
    PostThreadDirection direction = PostThreadDirection.up,
  });

  /// Returns followed CRT threads ordered by their latest activity.
  ///
  /// [before] is the root-post cursor for the next older page. Setting
  /// [extended] lets the server include participant profiles in the same
  /// response, avoiding a profile request per thread.
  Future<MattermostUserThreadsDto> getUserThreads({
    required String userId,
    required String teamId,
    int perPage = 60,
    String? before,
    bool extended = true,
    bool unread = false,
  });

  /// Advances the followed thread's read state to [timestamp], expressed as
  /// Unix milliseconds.
  Future<void> updateThreadRead({
    required String userId,
    required String teamId,
    required String threadId,
    required int timestamp,
  });

  /// Marks [channelId] viewed for [userId], advancing the server read state.
  Future<void> viewChannel({
    required String userId,
    required String channelId,
    String? previousChannelId,
  });

  /// Starts following a CRT thread for [userId].
  Future<void> followThread({
    required String userId,
    required String teamId,
    required String threadId,
  });

  /// Stops following a CRT thread for [userId].
  Future<void> unfollowThread({
    required String userId,
    required String teamId,
    required String threadId,
  });

  /// Returns the user's CRT thread state, or `null` when it is not followed.
  Future<MattermostUserThreadDto?> getUserThread({
    required String userId,
    required String teamId,
    required String threadId,
  }) => throw UnimplementedError();

  /// Returns preferences in one category, such as `postponed_messages`.
  Future<List<MattermostPreferenceDto>> getPreferencesByCategory({
    required String userId,
    required String category,
  });

  /// Creates or updates preferences. Mattermost accepts at most 100 per call.
  Future<void> savePreferences({
    required String userId,
    required List<MattermostPreferenceDto> preferences,
  });

  /// Deletes exact category/name preference entries. Mattermost accepts at
  /// most 100 entries per call.
  Future<void> deletePreferences({
    required String userId,
    required List<MattermostPreferenceDto> preferences,
  });
}

/// Authenticated profile-status commands layered on the shared API boundary.
///
/// Keeping these commands in a sub-interface lets focused repository fakes
/// implement only the API surface they exercise while production still routes
/// every request through [MattermostApi].
abstract interface class MattermostProfileApi implements MattermostApi {
  Future<MattermostUserStatusDto> updateUserStatus({
    required String userId,
    required String status,
    required int dndEndTime,
  });

  Future<void> updateUserCustomStatus({
    required String userId,
    required MattermostCustomStatusRequestDto status,
  });

  Future<void> removeUserCustomStatus(String userId);
}

/// Authenticated session commands used by the repository that owns the client.
abstract interface class MattermostSessionApi implements MattermostApi {
  Future<void> logout();
}
