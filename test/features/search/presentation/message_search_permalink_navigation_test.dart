import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/features/search/domain/models/message_search.dart'
    as models;
import 'package:mattermost_flutter/src/features/search/domain/repositories/message_search_repository.dart';
import 'package:mattermost_flutter/src/features/search/domain/repositories/message_search_timezone_repository.dart';
import 'package:mattermost_flutter/src/features/search/presentation/message_search_controller.dart';
import 'package:mattermost_flutter/src/features/search/presentation/message_search_page.dart';
import 'package:mattermost_flutter/src/features/search/presentation/message_search_suggestions_controller.dart';
import 'package:mattermost_flutter/src/ui/channels/selected_channel_controller.dart';
import 'package:mattermost_flutter/src/ui/posts/post_permalink_route.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  testWidgets(
    'opening a result preserves the Search snapshot, scroll, and selected channel',
    (WidgetTester tester) async {
      const _SearchRepository repository = _SearchRepository();
      const _TimezoneRepository timezoneRepository = _TimezoneRepository();
      final MessageSearchController searchController = MessageSearchController(
        repository: repository,
        timezoneRepository: timezoneRepository,
        session: _session,
        teamId: 'team',
        knownChannels: const <SidebarChannel>[_selectedChannel],
      );
      final MessageSearchSuggestionsController suggestionsController =
          MessageSearchSuggestionsController(
            repository: repository,
            teamId: 'team',
            knownChannels: const <SidebarChannel>[_selectedChannel],
          );
      final ProviderContainer container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWithValue(_session),
          messageSearchRepositoryProvider.overrideWithValue(repository),
          messageSearchTimezoneRepositoryProvider.overrideWithValue(
            timezoneRepository,
          ),
          messageSearchControllerProvider.overrideWithValue(searchController),
          messageSearchSuggestionsProvider.overrideWithValue(
            suggestionsController,
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(searchController.dispose);
      addTearDown(suggestionsController.dispose);
      container.read(selectedChannelProvider.notifier).select(_selectedChannel);

      final GoRouter router = GoRouter(
        initialLocation: '/search',
        routes: <RouteBase>[
          GoRoute(
            path: '/search',
            builder: (BuildContext context, GoRouterState state) =>
                const MessageSearchPage(),
          ),
          GoRoute(
            path: PostPermalinkRoute.path,
            builder: (BuildContext context, GoRouterState state) => Scaffold(
              body: Center(
                child: Text('Permalink ${state.pathParameters['postId']}'),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      final Finder field = find.byKey(
        const ValueKey<String>('message-search-field'),
      );
      await tester.tap(field);
      await tester.enterText(field, 'release');
      await searchController.submit();
      await tester.pumpAndSettle();

      final Finder target = find.byKey(
        const ValueKey<String>('message-search-result-post-10'),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();
      final ScrollableState resultsScrollable = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .firstWhere(
            (ScrollableState state) => state.position.maxScrollExtent > 0,
          );
      final double scrollOffset = resultsScrollable.position.pixels;
      expect(target, findsOneWidget);
      expect(scrollOffset, greaterThan(0));

      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('Permalink post-10'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('message-search-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('message-search-result-post-10')),
        findsOneWidget,
      );
      expect(resultsScrollable.position.pixels, closeTo(scrollOffset, 0.1));
      expect(container.read(selectedChannelProvider), same(_selectedChannel));
      expect(tester.takeException(), isNull);
    },
  );
}

final AuthSession _session = AuthSession(
  serverUrl: Uri.parse('https://chat.example.com'),
  userId: 'me',
  username: 'me',
);

const SidebarChannel _selectedChannel = SidebarChannel(
  id: 'selected-channel',
  teamId: 'team',
  name: 'selected',
  displayName: 'Selected channel',
  kind: ChannelKind.publicChannel,
);

final class _SearchRepository implements MessageSearchRepository {
  const _SearchRepository();

  @override
  Future<List<models.ChannelSearchSuggestion>> autocompleteChannels({
    required String teamId,
    required String prefix,
    Iterable<SidebarChannel> knownChannels = const <SidebarChannel>[],
  }) async => const <models.ChannelSearchSuggestion>[];

  @override
  Future<List<models.UserSearchSuggestion>> autocompleteUsers({
    required String teamId,
    required String prefix,
    int limit = 50,
  }) async => const <models.UserSearchSuggestion>[];

  @override
  Future<models.MessageSearchPage> search({
    required AuthSession session,
    required models.MessageSearchRequest request,
    Iterable<SidebarChannel> knownChannels = const <SidebarChannel>[],
  }) async => models.MessageSearchPage(
    page: 0,
    fingerprint: 'page-0',
    hasMore: false,
    results: List<models.MessageSearchResult>.generate(
      30,
      (int index) => models.MessageSearchResult(
        post: Post(
          id: 'post-$index',
          channelId: _selectedChannel.id,
          author: const PostAuthor(id: 'author', displayName: 'Author'),
          sentAt: DateTime.utc(2026, 9, 22, 12, index),
          message: 'Result $index',
        ),
        channel: _selectedChannel,
      ),
    ),
  );
}

final class _TimezoneRepository implements MessageSearchTimezoneRepository {
  const _TimezoneRepository();

  @override
  Future<MessageSearchTimezone> load() async =>
      MessageSearchTimezone(timezoneId: 'UTC', offsetSeconds: (_) => 0);
}
