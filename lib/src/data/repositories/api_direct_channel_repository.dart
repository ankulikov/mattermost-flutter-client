import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/channel_sidebar_mapper.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/repositories/direct_channel_repository.dart';

final class ApiDirectChannelRepository implements DirectChannelRepository {
  const ApiDirectChannelRepository({required MattermostApi api}) : _api = api;

  final MattermostApi _api;

  @override
  Future<SidebarChannel> open({
    required String currentUserId,
    required String otherUserId,
    required String otherUserDisplayName,
  }) async {
    final MattermostChannelDto dto = await _api.createDirectChannel(
      currentUserId: currentUserId,
      otherUserId: otherUserId,
    );
    return mapChannel(dto).withDisplayName(otherUserDisplayName);
  }
}
