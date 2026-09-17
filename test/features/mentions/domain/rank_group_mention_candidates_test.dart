import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/group_mention.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_candidate.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/policies/rank_group_mention_candidates.dart';

void main() {
  GroupMentionCandidate candidate(String id, String name, String displayName) =>
      GroupMentionCandidate(
        group: GroupMention(
          id: id,
          name: name,
          displayName: displayName,
          memberCount: 1,
        ),
      );

  test('ranks exact handle, handle prefix, then display-name prefix', () {
    final List<GroupMentionCandidate> result =
        rankGroupMentionCandidates(<GroupMentionCandidate>[
          candidate('4', 'zeta', 'Alpha Team'),
          candidate('3', 'alpha-two', 'Other'),
          candidate('2', 'alpha-one', 'Other'),
          candidate('1', 'alpha', 'Exact'),
        ], 'alpha');

    expect(
      result.map((GroupMentionCandidate value) => value.group.name),
      <String>['alpha', 'alpha-one', 'alpha-two', 'zeta'],
    );
  });

  test(
    'uses alphabetical handles and has no current-user membership input',
    () {
      final List<GroupMentionCandidate> result = rankGroupMentionCandidates(
        <GroupMentionCandidate>[
          candidate('2', 'backend', 'Backend'),
          candidate('1', 'android', 'Android'),
        ],
        '',
      );

      expect(
        result.map((GroupMentionCandidate value) => value.group.name),
        <String>['android', 'backend'],
      );
    },
  );
}
