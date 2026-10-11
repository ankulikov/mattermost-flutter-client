import 'package:mattermost_flutter/src/features/channel_members/domain/channel_member.dart';

abstract interface class ChannelMembersRepository {
  Future<int> getCount(String channelId);

  Future<ChannelMembersPage> loadPage({
    required String channelId,
    required int page,
    required int perPage,
  });
}
