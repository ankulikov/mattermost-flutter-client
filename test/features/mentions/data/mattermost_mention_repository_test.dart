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
        groups: const <MattermostGroupDto>[
          MattermostGroupDto(
            id: 'group-2',
            name: 'adam-team',
            displayName: 'Adam Team',
            allowReference: true,
            memberCount: 7,
          ),
          MattermostGroupDto(
            id: 'group-1',
            name: 'ad',
            displayName: 'Exact Group',
            allowReference: true,
            memberCount: 1,
          ),
          MattermostGroupDto(
            id: 'group-ignored',
            name: 'admin',
            displayName: 'Not mentionable',
          ),
        ],
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
      expect(result.groupMentions.map((value) => value.group.name), <String>[
        'ad',
        'adam-team',
      ]);
      expect(result.groupMentions.first.group.memberCount, 1);
    },
  );

  test('resolves exact group names without changing their handles', () async {
    final _AutocompleteApi api = _AutocompleteApi(
      const MattermostUserAutocompleteDto(users: <MattermostUserDto>[]),
      groupsByName: const <MattermostGroupDto>[
        MattermostGroupDto(
          id: 'group-1',
          name: 'backend',
          displayName: 'Backend Team',
          allowReference: true,
          memberCount: 12,
        ),
      ],
    );

    final groups = await MattermostMentionRepository(
      api: api,
    ).resolveGroupsByNames(<String>['backend']);

    expect(api.groupNames, <String>['backend']);
    expect(groups.single.name, 'backend');
    expect(groups.single.displayName, 'Backend Team');
  });

  test(
    'keeps user suggestions when optional group search is unavailable',
    () async {
      final _AutocompleteApi api = _AutocompleteApi(
        const MattermostUserAutocompleteDto(
          users: <MattermostUserDto>[
            MattermostUserDto(id: 'ada-id', username: 'ada'),
          ],
        ),
        groupsError: StateError('groups are not licensed'),
      );

      final result = await MattermostMentionRepository(
        api: api,
      ).autocomplete(teamId: 'team', channelId: 'channel', term: 'ada');

      expect(result.channelMembers.single.user.username, 'ada');
      expect(result.groupMentions, isEmpty);
    },
  );
}

final class _AutocompleteApi extends Fake implements MattermostApi {
  _AutocompleteApi(
    this.response, {
    this.groups = const <MattermostGroupDto>[],
    this.groupsByName = const <MattermostGroupDto>[],
    this.groupsError,
  });

  final MattermostUserAutocompleteDto response;
  final List<MattermostGroupDto> groups;
  final List<MattermostGroupDto> groupsByName;
  final Object? groupsError;
  String? teamId;
  String? channelId;
  String? name;
  int? limit;
  List<String>? groupNames;

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

  @override
  Future<List<MattermostGroupDto>> searchMentionGroups({
    required String name,
    required int limit,
  }) async {
    final Object? error = groupsError;
    if (error != null) throw error;
    return groups;
  }

  @override
  Future<List<MattermostGroupDto>> getGroupsByNames(List<String> names) async {
    groupNames = names;
    return groupsByName;
  }
}
