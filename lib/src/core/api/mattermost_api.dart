import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';

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

  Future<MattermostChannelCategoriesDto> getChannelCategories({
    required String userId,
    required String teamId,
  });

  Future<List<MattermostUserDto>> getUsersByIds(List<String> userIds);

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

  /// Returns posts modified after [since] (Unix milliseconds). Mattermost may
  /// return up to 1000 non-consecutive posts, so callers must reconcile holes.
  Future<MattermostPostListDto> getPostsSince({
    required String channelId,
    required int since,
  });

  /// Creates a channel post or a threaded reply through the REST API.
  Future<MattermostPostDto> createPost(MattermostCreatePostRequestDto post);

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
}
