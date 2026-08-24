import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';

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

  Future<MattermostGroupChannelUsersDto> getUsersForGroupChannels(
    List<String> channelIds,
  );

  Future<MattermostPostListDto> getPostsForChannel({
    required String channelId,
    int page = 0,
    int perPage = 60,
    String? etag,
  });
}
