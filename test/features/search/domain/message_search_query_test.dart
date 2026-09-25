import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/features/search/domain/models/message_search.dart';
import 'package:mattermost_flutter/src/features/search/domain/policies/message_search_pagination.dart';
import 'package:mattermost_flutter/src/features/search/domain/policies/message_search_query.dart';

void main() {
  group('message search query', () {
    test('finds the case-insensitive filter at the caret only', () {
      const String query = 'text FROM:ad in:town';

      final ActiveSearchFilter? from = activeMessageSearchFilter(query, 11);
      final ActiveSearchFilter? inChannel = activeMessageSearchFilter(
        query,
        query.length,
      );

      expect(from?.kind, SearchFilterKind.from);
      expect(from?.valueStart, 10);
      expect(from?.valueEnd, 12);
      expect(inChannel?.kind, SearchFilterKind.inChannel);
      expect(activeMessageSearchFilter(query, 4), isNull);
    });

    test('keeps quoted phrases and normalizes curly quotes only on submit', () {
      const String query = '  “exact phrase” from:ada ‘another phrase’  ';

      expect(
        normalizeMessageSearchTerms(query),
        '"exact phrase" from:ada \'another phrase\'',
      );
      expect(canSubmitMessageSearch(' in:town'), isTrue);
      expect(canSubmitMessageSearch(' \n\t '), isFalse);
    });

    test('keeps a quoted filter value as one caret-aware fragment', () {
      const String query = 'in:"Town Square" after:2026-01-01';

      final ActiveSearchFilter? active = activeMessageSearchFilter(query, 12);

      expect(active?.kind, SearchFilterKind.inChannel);
      expect(
        insertMessageSearchSuggestion(
          query: query,
          caretOffset: 12,
          replacement: 'town-square',
        ),
        'in:town-square after:2026-01-01',
      );
    });

    test('replaces only the active value and leaves suffix intact', () {
      expect(
        insertMessageSearchSuggestion(
          query: 'before:2026-01-01 from:old text',
          caretOffset: 24,
          replacement: 'ada',
        ),
        'before:2026-01-01 from:ada text',
      );
    });

    test(
      'inserts a filter prefix without a trailing space for suggestions',
      () {
        expect(
          insertMessageSearchFilterPrefix(
            query: 'urgenttomorrow',
            caretOffset: 6,
            kind: SearchFilterKind.after,
          ),
          'urgent after:tomorrow',
        );
        expect(
          insertMessageSearchFilterPrefix(
            query: '',
            caretOffset: 0,
            kind: SearchFilterKind.inChannel,
          ),
          'in:',
        );
      },
    );

    test('formats the chosen local calendar day without UTC conversion', () {
      expect(
        formatMessageSearchDate(DateTime(2026, 1, 2, 0, 0).toLocal()),
        '2026-01-02',
      );
      expect(
        formatMessageSearchDate(DateTime(2026, 12, 31, 23, 59)),
        '2026-12-31',
      );
    });
  });

  test('ends pagination when the next server page repeats', () {
    final MessageSearchPage merged = mergeMessageSearchPages(
      current: _page(<String>['one'], fingerprint: 'one', hasMore: true),
      incoming: _page(<String>['one'], fingerprint: 'one', hasMore: true),
    );

    expect(
      merged.results.map((MessageSearchResult result) => result.post.id),
      <String>['one'],
    );
    expect(merged.hasMore, isFalse);
  });
}

MessageSearchPage _page(
  List<String> ids, {
  required String fingerprint,
  required bool hasMore,
}) => MessageSearchPage(
  results: ids.map(_result).toList(growable: false),
  page: 0,
  hasMore: hasMore,
  fingerprint: fingerprint,
);

MessageSearchResult _result(String id) => MessageSearchResult(
  post: Post(
    id: id,
    channelId: 'channel',
    author: const PostAuthor(id: 'user', displayName: 'User'),
    sentAt: DateTime(2026),
    message: id,
  ),
  channel: const SidebarChannel(
    id: 'channel',
    teamId: 'team',
    name: 'town-square',
    displayName: 'Town Square',
    kind: ChannelKind.publicChannel,
  ),
);
