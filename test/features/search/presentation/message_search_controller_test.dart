import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/features/search/domain/models/message_search.dart';
import 'package:mattermost_flutter/src/features/search/domain/repositories/message_search_repository.dart';
import 'package:mattermost_flutter/src/features/search/domain/repositories/message_search_timezone_repository.dart';
import 'package:mattermost_flutter/src/features/search/presentation/message_search_controller.dart';

void main() {
  group('MessageSearchController', () {
    test('keeps draft separate and submits its normalized value', () async {
      final _SearchRepository repository = _SearchRepository();
      final MessageSearchController controller = _controller(repository);

      controller.updateDraft('  “needle”  ');
      expect(controller.state.phase, MessageSearchPhase.initial);
      expect(repository.requests, isEmpty);

      final Future<void> submit = controller.submit();
      expect(controller.state.phase, MessageSearchPhase.initialLoading);
      await _waitForRequests(repository, 1);
      repository.completeNext(_page('first', <String>['a'], hasMore: true));
      await submit;

      expect(repository.requests.single.terms, '"needle"');
      expect(controller.state.draftQuery, '  “needle”  ');
      expect(controller.state.submittedQuery, '"needle"');
      expect(controller.state.results.single.post.id, 'a');
      expect(controller.state.hasMore, isTrue);
      controller.dispose();
    });

    test('a new submit cancels and ignores an older search response', () async {
      final _SearchRepository repository = _SearchRepository();
      final MessageSearchController controller = _controller(repository);

      controller.updateDraft('first');
      final Future<void> first = controller.submit();
      await _waitForRequests(repository, 1);
      controller.updateDraft('second');
      final Future<void> second = controller.submit();
      await _waitForRequests(repository, 2);

      repository.completeAt(0, _page('first', <String>['old']));
      await first;
      expect(controller.state.phase, MessageSearchPhase.initialLoading);
      repository.completeAt(1, _page('second', <String>['new']));
      await second;

      expect(controller.state.submittedQuery, 'second');
      expect(controller.state.results.single.post.id, 'new');
      controller.dispose();
    });

    test(
      'initial failure is retryable with the last submitted query',
      () async {
        final _SearchRepository repository = _SearchRepository();
        final MessageSearchController controller = _controller(repository);
        controller.updateDraft('needle');
        final Future<void> initial = controller.submit();
        await _waitForRequests(repository, 1);
        repository.failNext(StateError('offline'));
        await initial;

        expect(controller.state.phase, MessageSearchPhase.initialError);
        expect(controller.state.initialError, isA<StateError>());
        controller.updateDraft('different draft');
        final Future<void> retry = controller.retry();
        await _waitForRequests(repository, 2);
        expect(repository.requests.last.terms, 'needle');
        repository.completeNext(_page('first', <String>['a']));
        await retry;
        expect(controller.state.phase, MessageSearchPhase.data);
        controller.dispose();
      },
    );

    test(
      'refresh preserves data on failure and retry repeats submitted query',
      () async {
        final _SearchRepository repository = _SearchRepository();
        final MessageSearchController controller = _controller(repository);
        controller.updateDraft('needle');
        final Future<void> initial = controller.submit();
        await _waitForRequests(repository, 1);
        repository.completeNext(_page('first', <String>['a']));
        await initial;

        final Future<void> refresh = controller.refresh();
        expect(controller.state.isRefreshing, isTrue);
        expect(controller.state.results.single.post.id, 'a');
        await _waitForRequests(repository, 2);
        repository.failNext(StateError('offline'));
        await refresh;
        expect(controller.state.phase, MessageSearchPhase.data);
        expect(controller.state.refreshError, isA<StateError>());

        controller.updateDraft('different draft');
        final Future<void> retry = controller.retry();
        await _waitForRequests(repository, 3);
        expect(repository.requests.last.terms, 'needle');
        repository.completeNext(_page('retry', <String>['b']));
        await retry;
        expect(controller.state.results.single.post.id, 'b');
        controller.dispose();
      },
    );

    test('pagination merges unique posts and stops a repeated page', () async {
      final _SearchRepository repository = _SearchRepository();
      final MessageSearchController controller = _controller(repository);
      controller.updateDraft('needle');
      final Future<void> initial = controller.submit();
      await _waitForRequests(repository, 1);
      repository.completeNext(_page('first', <String>['a'], hasMore: true));
      await initial;

      final Future<void> more = controller.loadMore();
      expect(controller.state.isLoadingMore, isTrue);
      await _waitForRequests(repository, 2);
      repository.completeNext(
        _page('second', <String>['a', 'b'], hasMore: true),
      );
      await more;
      expect(
        controller.state.results.map(
          (MessageSearchResult item) => item.post.id,
        ),
        <String>['a', 'b'],
      );
      expect(controller.state.nextPage, 2);

      final Future<void> repeated = controller.loadMore();
      await _waitForRequests(repository, 3);
      repository.completeNext(
        _page('second', <String>['a', 'b'], hasMore: true),
      );
      await repeated;
      expect(controller.state.hasMore, isFalse);
      expect(controller.state.paginationError, isNull);
      controller.dispose();
    });

    test(
      'context reset cancels work and launch intent cannot overwrite input',
      () async {
        final _SearchRepository repository = _SearchRepository();
        final MessageSearchController controller = _controller(repository);
        controller.updateDraft('needle');
        final Future<void> pending = controller.submit();
        await _waitForRequests(repository, 1);
        controller.updateContext(session: _session, teamId: 'other');
        repository.completeNext(_page('first', <String>['a']));
        await pending;
        expect(controller.state.phase, MessageSearchPhase.initial);
        expect(controller.state.results, isEmpty);

        const SearchLaunchIntent intent = SearchLaunchIntent(
          teamId: 'other',
          initialQuery: 'in:town ',
          focus: true,
          nonce: 'one',
        );
        expect(controller.consumeLaunchIntent(intent), isTrue);
        expect(controller.state.draftQuery, 'in:town ');
        expect(controller.state.focusRequestNonce, 'one');
        controller.updateDraft('typed');
        expect(
          controller.consumeLaunchIntent(
            const SearchLaunchIntent(
              teamId: 'other',
              initialQuery: 'in:elsewhere ',
              focus: true,
              nonce: 'two',
            ),
          ),
          isFalse,
        );
        expect(controller.state.draftQuery, 'typed');
        controller.dispose();
      },
    );
  });
}

MessageSearchController _controller(_SearchRepository repository) =>
    MessageSearchController(
      repository: repository,
      timezoneRepository: const _TimezoneRepository(),
      session: _session,
      teamId: 'team',
      clock: () => DateTime.utc(2026),
    );

final AuthSession _session = AuthSession(
  serverUrl: Uri(scheme: 'https', host: 'chat.example'),
  userId: 'me',
  username: 'me',
);

Future<void> _waitForRequests(_SearchRepository repository, int count) async {
  while (repository.requests.length < count) {
    await Future<void>.delayed(Duration.zero);
  }
}

MessageSearchPage _page(
  String fingerprint,
  List<String> ids, {
  bool hasMore = false,
}) => MessageSearchPage(
  page: fingerprint == 'first' ? 0 : 1,
  fingerprint: fingerprint,
  hasMore: hasMore,
  results: ids
      .map(
        (String id) => MessageSearchResult(
          post: Post(
            id: id,
            channelId: 'channel',
            author: const PostAuthor(id: 'author', displayName: 'Author'),
            sentAt: DateTime.utc(2026),
            message: id,
          ),
          channel: const SidebarChannel(
            id: 'channel',
            teamId: 'team',
            name: 'town',
            displayName: 'Town',
            kind: ChannelKind.publicChannel,
          ),
        ),
      )
      .toList(growable: false),
);

final class _TimezoneRepository implements MessageSearchTimezoneRepository {
  const _TimezoneRepository();

  @override
  Future<MessageSearchTimezone> load() async =>
      MessageSearchTimezone(timezoneId: 'UTC', offsetSeconds: (_) => 0);
}

final class _SearchRepository implements MessageSearchRepository {
  final List<MessageSearchRequest> requests = <MessageSearchRequest>[];
  final List<Completer<MessageSearchPage>> _responses =
      <Completer<MessageSearchPage>>[];

  @override
  Future<MessageSearchPage> search({
    required AuthSession session,
    required MessageSearchRequest request,
    Iterable<SidebarChannel> knownChannels = const <SidebarChannel>[],
  }) {
    requests.add(request);
    final Completer<MessageSearchPage> response =
        Completer<MessageSearchPage>();
    _responses.add(response);
    return response.future;
  }

  void completeNext(MessageSearchPage page) => _responses
      .firstWhere(
        (Completer<MessageSearchPage> response) => !response.isCompleted,
      )
      .complete(page);

  void completeAt(int index, MessageSearchPage page) =>
      _responses[index].complete(page);

  void failNext(Object error) => _responses
      .firstWhere(
        (Completer<MessageSearchPage> response) => !response.isCompleted,
      )
      .completeError(error);

  @override
  Future<List<UserSearchSuggestion>> autocompleteUsers({
    required String teamId,
    required String prefix,
    int limit = 50,
  }) async => const <UserSearchSuggestion>[];

  @override
  Future<List<ChannelSearchSuggestion>> autocompleteChannels({
    required String teamId,
    required String prefix,
    Iterable<SidebarChannel> knownChannels = const <SidebarChannel>[],
  }) async => const <ChannelSearchSuggestion>[];
}
