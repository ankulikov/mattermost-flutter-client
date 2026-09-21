import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/search/domain/models/message_search.dart';
import 'package:mattermost_flutter/src/features/search/domain/repositories/message_search_repository.dart';
import 'package:mattermost_flutter/src/features/search/presentation/message_search_suggestions_controller.dart';

void main() {
  test('a late result for an older prefix is ignored', () async {
    final _SuggestionsRepository repository = _SuggestionsRepository();
    final MessageSearchSuggestionsController controller =
        MessageSearchSuggestionsController(
          repository: repository,
          teamId: 'team',
          debounce: Duration.zero,
        );
    controller.update(query: 'from:a', caretOffset: 6);
    await Future<void>.delayed(Duration.zero);
    controller.update(query: 'from:b', caretOffset: 6);
    await Future<void>.delayed(Duration.zero);

    repository.first.complete(const <UserSearchSuggestion>[
      UserSearchSuggestion(_ada),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.status, MessageSearchSuggestionStatus.loading);

    repository.second.complete(const <UserSearchSuggestion>[
      UserSearchSuggestion(_bea),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.suggestions.single.replacement, 'bea');
    controller.dispose();
  });

  test('date filters show calendar state without a network request', () {
    final _SuggestionsRepository repository = _SuggestionsRepository();
    final MessageSearchSuggestionsController controller =
        MessageSearchSuggestionsController(
          repository: repository,
          teamId: 'team',
        );

    controller.update(query: 'after:', caretOffset: 6);

    expect(controller.state.showsCalendar, isTrue);
    expect(repository.calls, isZero);
    expect(
      controller.insertDate(
        query: 'after:',
        caretOffset: 6,
        date: DateTime(2026, 3, 29),
      ),
      'after:2026-03-29 ',
    );
    controller.dispose();
  });
}

const UserSummary _ada = UserSummary(
  id: 'ada',
  username: 'ada',
  firstName: '',
  lastName: '',
  nickname: '',
  position: '',
  email: '',
);
const UserSummary _bea = UserSummary(
  id: 'bea',
  username: 'bea',
  firstName: '',
  lastName: '',
  nickname: '',
  position: '',
  email: '',
);

final class _SuggestionsRepository implements MessageSearchRepository {
  final Completer<List<UserSearchSuggestion>> first =
      Completer<List<UserSearchSuggestion>>();
  final Completer<List<UserSearchSuggestion>> second =
      Completer<List<UserSearchSuggestion>>();
  int calls = 0;

  @override
  Future<List<UserSearchSuggestion>> autocompleteUsers({
    required String teamId,
    required String prefix,
    int limit = 50,
  }) {
    calls += 1;
    return calls == 1 ? first.future : second.future;
  }

  @override
  Future<List<ChannelSearchSuggestion>> autocompleteChannels({
    required String teamId,
    required String prefix,
    Iterable<SidebarChannel> knownChannels = const <SidebarChannel>[],
  }) async => const <ChannelSearchSuggestion>[];

  @override
  Future<MessageSearchPage> search({
    required AuthSession session,
    required MessageSearchRequest request,
    Iterable<SidebarChannel> knownChannels = const <SidebarChannel>[],
  }) => throw UnimplementedError();
}
