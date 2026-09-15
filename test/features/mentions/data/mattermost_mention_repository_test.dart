import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/mentions/data/repositories/mattermost_mention_repository.dart';

void main() {
  test(
    'keeps member priority and drops agents, duplicates, malformed, inactive users',
    () async {
      final _AutocompleteApi api = _AutocompleteApi(
        const MattermostUserAutocompleteDto(
          users: <MattermostUserDto>[
            MattermostUserDto(id: 'member', username: 'ada'),
            MattermostUserDto(id: 'agent', username: 'helper'),
            MattermostUserDto(id: '', username: 'missing-id'),
            MattermostUserDto(id: 'inactive', username: 'old', deleteAt: 1),
          ],
          outOfChannel: <MattermostUserDto>[
            MattermostUserDto(id: 'member', username: 'ada'),
            MattermostUserDto(id: 'outside', username: 'adam'),
            MattermostUserDto(id: 'no-handle', username: ''),
          ],
          agents: <MattermostUserDto>[
            MattermostUserDto(id: 'agent', username: 'helper'),
          ],
        ),
      );

      final result = await MattermostMentionRepository(api: api).autocomplete(
        teamId: 'team',
        channelId: 'channel',
        term: 'ad',
        limit: 12,
      );

      expect(api.teamId, 'team');
      expect(api.channelId, 'channel');
      expect(api.name, 'ad');
      expect(api.limit, 12);
      expect(result.channelMembers.map((value) => value.user.id), <String>[
        'member',
      ]);
      expect(result.notInChannel.map((value) => value.user.id), <String>[
        'outside',
      ]);
    },
  );
}

final class _AutocompleteApi extends Fake implements MattermostApi {
  _AutocompleteApi(this.response);

  final MattermostUserAutocompleteDto response;
  String? teamId;
  String? channelId;
  String? name;
  int? limit;

  @override
  Future<MattermostUserAutocompleteDto> autocompleteUsers({
    required String teamId,
    required String channelId,
    required String name,
    required int limit,
  }) async {
    this.teamId = teamId;
    this.channelId = channelId;
    this.name = name;
    this.limit = limit;
    return response;
  }
}
