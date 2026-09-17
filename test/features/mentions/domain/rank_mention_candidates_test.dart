import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_candidate.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/policies/rank_mention_candidates.dart';

void main() {
  MentionCandidate candidate(
    String id,
    String username, {
    String firstName = '',
  }) => MentionCandidate(
    user: UserSummary(
      id: id,
      username: username,
      firstName: firstName,
      lastName: '',
      nickname: '',
      position: '',
      email: '',
    ),
  );

  test(
    'ranks exact handle, handle prefix, display-name prefix, then username',
    () {
      final List<MentionCandidate> result =
          rankMentionCandidates(<MentionCandidate>[
            candidate('4', 'zoe', firstName: 'Adam'),
            candidate('3', 'alpine'),
            candidate('2', 'alpha'),
            candidate('1', 'al'),
          ], 'al');

      expect(
        result.map((MentionCandidate value) => value.user.username),
        <String>['al', 'alpha', 'alpine', 'zoe'],
      );
    },
  );

  test('compares case-insensitively and remains deterministic', () {
    final List<MentionCandidate> result = rankMentionCandidates(
      <MentionCandidate>[candidate('b', 'Bravo'), candidate('a', 'alpha')],
      'missing',
    );

    expect(result.map((MentionCandidate value) => value.user.id), <String>[
      'a',
      'b',
    ]);
  });
}
