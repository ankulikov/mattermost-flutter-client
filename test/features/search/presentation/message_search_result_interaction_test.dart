import 'dart:ui' show PointerDeviceKind;

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
import 'package:mattermost_flutter/src/ui/posts/post_permalink_route.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  testWidgets(
    'result uses the channel hover highlight and clears it after a touch tap',
    (WidgetTester tester) async {
      const _SearchRepository repository = _SearchRepository();
      const _TimezoneRepository timezoneRepository = _TimezoneRepository();
      final MessageSearchController searchController = MessageSearchController(
        repository: repository,
        timezoneRepository: timezoneRepository,
        session: _session,
        teamId: _channel.teamId,
        knownChannels: const <SidebarChannel>[_channel],
      );
      final MessageSearchSuggestionsController suggestionsController =
          MessageSearchSuggestionsController(
            repository: repository,
            teamId: _channel.teamId,
            knownChannels: const <SidebarChannel>[_channel],
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
            builder: (BuildContext context, GoRouterState state) =>
                const Scaffold(),
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
      final Finder field = find.byKey(
        const ValueKey<String>('message-search-field'),
      );
      await tester.enterText(field, 'result');
      await searchController.submit();
      await tester.pumpAndSettle();

      final Finder highlight = find.byKey(
        const ValueKey<String>('message-search-result-post'),
      );
      expect(_color(tester, highlight), Colors.transparent);

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(highlight));
      await tester.pumpAndSettle();
      expect(
        _color(tester, highlight),
        Theme.of(
          tester.element(highlight),
        ).colorScheme.primary.withValues(alpha: 0.10),
      );
      await mouse.moveTo(const Offset(0, 0));
      await tester.pumpAndSettle();

      await tester.tap(highlight, kind: PointerDeviceKind.touch);
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();

      expect(_color(tester, highlight), Colors.transparent);
    },
  );
}

Color _color(WidgetTester tester, Finder finder) {
  final BoxDecoration decoration =
      tester.widget<AnimatedContainer>(finder).decoration! as BoxDecoration;
  return decoration.color!;
}

final AuthSession _session = AuthSession(
  serverUrl: Uri.parse('https://chat.example.com'),
  userId: 'me',
  username: 'me',
);

const SidebarChannel _channel = SidebarChannel(
  id: 'channel',
  teamId: 'team',
  name: 'channel',
  displayName: 'Channel',
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
    results: <models.MessageSearchResult>[
      models.MessageSearchResult(
        post: Post(
          id: 'post',
          channelId: _channel.id,
          author: PostAuthor(id: 'author', displayName: 'Author'),
          sentAt: DateTime.utc(2026, 9, 22),
          message: 'Result',
        ),
        channel: _channel,
      ),
    ],
  );
}

final class _TimezoneRepository implements MessageSearchTimezoneRepository {
  const _TimezoneRepository();

  @override
  Future<MessageSearchTimezone> load() async =>
      MessageSearchTimezone(timezoneId: 'UTC', offsetSeconds: (_) => 0);
}
