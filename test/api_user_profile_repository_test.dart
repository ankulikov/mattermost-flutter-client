import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/channels/data/api_direct_channel_repository.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';
import 'package:mattermost_flutter/src/features/users/data/api_user_profile_repository.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_profile.dart';

void main() {
  test('maps complete profile and presence loaded by user id', () async {
    final _ProfileApi api = _ProfileApi();
    final UserProfile profile = await ApiUserProfileRepository(
      api: api,
    ).getById('ada');

    expect(api.requestedUserId, 'ada');
    expect(api.statusUserId, 'ada');
    expect(profile.fullName, 'Ada Lovelace');
    expect(profile.handle, 'ada-nickname');
    expect(profile.position, 'Mathematician');
    expect(profile.email, 'ada@example.com');
    expect(profile.presence, UserPresence.online);
    expect(profile.profileImageUpdatedAt, 42);
  });

  test('creates and maps a direct channel with the profile name', () async {
    final _ProfileApi api = _ProfileApi();
    final SidebarChannel channel = await ApiDirectChannelRepository(api: api)
        .open(
          currentUserId: 'me',
          otherUserId: 'ada',
          otherUserDisplayName: 'Ada Lovelace',
        );

    expect(api.directUsers, ('me', 'ada'));
    expect(channel.id, 'direct-1');
    expect(channel.kind, ChannelKind.directMessage);
    expect(channel.displayName, 'Ada Lovelace');
  });
}

final class _ProfileApi implements MattermostApi {
  String? requestedUserId;
  String? statusUserId;
  (String, String)? directUsers;

  @override
  Future<MattermostUserDto> getUserById(String userId) async {
    requestedUserId = userId;
    return const MattermostUserDto(
      id: 'ada',
      username: 'ada',
      firstName: 'Ada',
      lastName: 'Lovelace',
      nickname: 'ada-nickname',
      position: 'Mathematician',
      email: 'ada@example.com',
      lastPictureUpdate: 42,
    );
  }

  @override
  Future<MattermostUserStatusDto> getUserStatus(String userId) async {
    statusUserId = userId;
    return const MattermostUserStatusDto(userId: 'ada', status: 'online');
  }

  @override
  Future<MattermostChannelDto> createDirectChannel({
    required String currentUserId,
    required String otherUserId,
  }) async {
    directUsers = (currentUserId, otherUserId);
    return const MattermostChannelDto(
      id: 'direct-1',
      teamId: '',
      type: 'D',
      displayName: '',
      name: 'ada__me',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
