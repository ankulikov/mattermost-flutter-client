import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/mention_query.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_candidate.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_search_result.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/repositories/mention_repository.dart';
import 'package:mattermost_flutter/src/features/mentions/presentation/mention_autocomplete_controller.dart';

void main() {
  const MentionQuery query = MentionQuery(
    start: 0,
    end: 3,
    trigger: '@',
    term: 'ann',
    key: 'ann',
  );

  test('debounces searches and serves an exact in-memory cache hit', () async {
    final _FakeRepository repository = _FakeRepository();
    final MentionAutocompleteController controller =
        MentionAutocompleteController(
          repository: repository,
          teamId: 'team',
          channelId: 'channel',
          debounce: Duration.zero,
        );
    addTearDown(controller.dispose);

    controller.updateQuery(query);
    await _settle();
    expect(repository.terms, <String>['ann']);
    expect(controller.state.status, MentionAutocompleteStatus.data);

    controller.updateQuery(null);
    controller.updateQuery(query);
    expect(controller.state.status, MentionAutocompleteStatus.data);
    expect(repository.terms, <String>['ann']);
  });

  test('retains useful data while the next query is loading', () async {
    final _FakeRepository repository = _FakeRepository();
    final MentionAutocompleteController controller =
        MentionAutocompleteController(
          repository: repository,
          teamId: 'team',
          channelId: 'channel',
          debounce: const Duration(days: 1),
        );
    addTearDown(controller.dispose);
    controller.updateQuery(query);
    controller.updateQuery(
      const MentionQuery(
        start: 0,
        end: 4,
        trigger: '@',
        term: 'anna',
        key: 'anna',
      ),
    );
    expect(controller.state.status, MentionAutocompleteStatus.loading);
    expect(controller.state.result, isNull);
  });

  test('dismiss cancels a pending query and returns to idle', () {
    final MentionAutocompleteController controller =
        MentionAutocompleteController(
          repository: _FakeRepository(),
          teamId: 'team',
          channelId: 'channel',
          debounce: const Duration(days: 1),
        );
    addTearDown(controller.dispose);
    controller.updateQuery(query);
    controller.dismiss();
    expect(controller.state.status, MentionAutocompleteStatus.idle);
    expect(controller.state.query, isNull);
  });
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

final class _FakeRepository implements MentionRepository {
  final List<String> terms = <String>[];

  @override
  Future<MentionSearchResult> autocomplete({
    required String teamId,
    required String channelId,
    required String term,
    int limit = 30,
  }) async {
    terms.add(term);
    return MentionSearchResult(
      channelMembers: <MentionCandidate>[
        MentionCandidate(
          user: const UserSummary(
            id: 'ann',
            firstName: 'Ann',
            lastName: 'Example',
            username: 'ann',
            nickname: '',
            position: '',
            email: '',
          ),
        ),
      ],
      notInChannel: const <MentionCandidate>[],
    );
  }
}
