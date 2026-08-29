import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_display_name.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_mention.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_mention_repository.dart';

final class ApiUserMentionRepository implements UserMentionRepository {
  const ApiUserMentionRepository({required MattermostApi api}) : _api = api;

  final MattermostApi _api;

  @override
  Future<List<UserMention>> resolveUsernames(List<String> usernames) async {
    final List<String> requested = usernames
        .map((String username) => username.trim().toLowerCase())
        .where((String username) => username.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (requested.isEmpty) return const <UserMention>[];

    final List<MattermostUserDto> users = await _api.getUsersByUsernames(
      requested,
    );
    return users
        .where(
          (MattermostUserDto user) =>
              user.id.isNotEmpty &&
              requested.contains(user.username.toLowerCase()),
        )
        .map(
          (MattermostUserDto user) => UserMention(
            userId: user.id,
            username: user.username,
            displayName: resolveUserDisplayName(
              id: user.id,
              username: user.username,
              nickname: user.nickname,
              firstName: user.firstName,
              lastName: user.lastName,
            ),
          ),
        )
        .toList(growable: false);
  }
}
