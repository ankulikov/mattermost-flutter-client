import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_counters.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_page.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/mattermost_markdown.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  testWidgets('shows stored tab counts while the first snapshot is loading', (
    WidgetTester tester,
  ) async {
    final Completer<InboxSnapshot> snapshot = Completer<InboxSnapshot>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(_session),
          inboxRepositoryProvider.overrideWithValue(
            _SequencedInboxRepository(
              <Future<InboxSnapshot> Function()>[() => snapshot.future],
              counters: const InboxCounters(
                newMessages: 7,
                postponedMessages: 3,
              ),
            ),
          ),
          postponedRepositoryProvider.overrideWithValue(
            const _PostponedRepository(),
          ),
        ],
        child: MaterialApp(home: InboxPage(onOpenItem: (_) {})),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('inbox-new-count')))
          .data,
      '7',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('inbox-postponed-count')),
          )
          .data,
      '3',
    );

    snapshot.complete(InboxSnapshot());
    await tester.pumpAndSettle();
  });

  testWidgets('retries an initial Inbox load without discarding tab counts', (
    WidgetTester tester,
  ) async {
    final _SequencedInboxRepository repository = _SequencedInboxRepository(
      <Future<InboxSnapshot> Function()>[
        () async => throw StateError('offline'),
        () async => InboxSnapshot(),
      ],
      counters: const InboxCounters(newMessages: 5, postponedMessages: 1),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(_session),
          inboxRepositoryProvider.overrideWithValue(repository),
          postponedRepositoryProvider.overrideWithValue(
            const _PostponedRepository(),
          ),
        ],
        child: MaterialApp(home: InboxPage(onOpenItem: (_) {})),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(InboxStrings.loadFailed), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('inbox-new-count')))
          .data,
      '5',
    );

    await tester.tap(find.text(InboxStrings.retry));
    await tester.pumpAndSettle();

    expect(repository.loadCalls, 2);
    expect(find.text(InboxStrings.emptyNew), findsOneWidget);
  });

  testWidgets('shows red, yellow and green realtime connection indicators', (
    WidgetTester tester,
  ) async {
    final StreamController<InboxRealtimeEvent> realtime =
        StreamController<InboxRealtimeEvent>();
    addTearDown(realtime.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(_session),
          inboxRepositoryProvider.overrideWithValue(
            _InboxRepository(InboxSnapshot(), realtime: realtime.stream),
          ),
          postponedRepositoryProvider.overrideWithValue(
            const _PostponedRepository(),
          ),
        ],
        child: MaterialApp(home: InboxPage(onOpenItem: (_) {})),
      ),
    );
    await tester.pumpAndSettle();

    final Finder indicator = find.byKey(
      const ValueKey<String>('inbox-connection-indicator'),
    );
    expect(indicator, findsOneWidget);
    expect(find.byTooltip('Inbox realtime is disconnected'), findsOneWidget);
    expect(
      tester
          .widget<Container>(
            find.descendant(of: indicator, matching: find.byType(Container)),
          )
          .decoration,
      isA<BoxDecoration>().having(
        (BoxDecoration decoration) => decoration.color,
        'color',
        Colors.red,
      ),
    );

    realtime.add(
      const InboxConnectionChanged(InboxConnectionStatus.connecting),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Inbox realtime is connecting'), findsOneWidget);
    expect(
      tester
          .widget<Container>(
            find.descendant(of: indicator, matching: find.byType(Container)),
          )
          .decoration,
      isA<BoxDecoration>().having(
        (BoxDecoration decoration) => decoration.color,
        'color',
        Colors.amber,
      ),
    );

    realtime.add(const InboxConnectionChanged(InboxConnectionStatus.connected));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Inbox realtime is connected'), findsOneWidget);
    expect(
      tester
          .widget<Container>(
            find.descendant(of: indicator, matching: find.byType(Container)),
          )
          .decoration,
      isA<BoxDecoration>().having(
        (BoxDecoration decoration) => decoration.color,
        'color',
        Colors.green,
      ),
    );
  });

  testWidgets(
    'shows plain headers, update tags, markdown, and newest activity first',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final List<InboxItem> items = _items();
      final _InboxRepository repository = _InboxRepository(
        InboxSnapshot(newItems: items),
      );
      InboxItem? opened;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWithValue(_session),
            inboxRepositoryProvider.overrideWithValue(repository),
            postponedRepositoryProvider.overrideWithValue(
              const _PostponedRepository(),
            ),
          ],
          child: MaterialApp(
            home: InboxPage(onOpenItem: (InboxItem item) => opened = item),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mentions'), findsNothing);
      expect(find.text('Direct Messages'), findsNothing);
      expect(find.text('Threads'), findsNothing);
      expect(find.text('Thread in Town Square'), findsNothing);
      expect(find.text('@dev-team in Town Square'), findsNothing);
      expect(find.text('You mentioned in Town Square'), findsNothing);
      expect(find.text('Direct message'), findsOneWidget);
      expect(find.text('Town Square'), findsNWidgets(4));
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('inbox-source-thread:root')),
            )
            .data,
        'Town Square',
      );
      expect(find.text('new replies, last one at'), findsOneWidget);
      expect(find.text('messages since'), findsOneWidget);
      expect(find.text('new messages, last one at'), findsNothing);
      final Finder dmSinceDate = find.byKey(
        const ValueKey<String>('inbox-update-trailing-tag-direct:dm:dm-1-0-0'),
      );
      final String firstMessageDate = MaterialLocalizations.of(
        tester.element(dmSinceDate),
      ).formatMediumDate(DateTime.utc(2026, 9, 4).toLocal());
      expect(
        find.descendant(of: dmSinceDate, matching: find.text(firstMessageDate)),
        findsOneWidget,
      );
      expect(find.text('mentioned'), findsNWidgets(3));
      expect(find.text('You'), findsNWidgets(2));
      expect(find.text('@dev-team'), findsNWidgets(2));
      expect(find.text('New post in a channel'), findsOneWidget);
      expect(
        tester
            .getTopLeft(
              find.byKey(
                const ValueKey<String>('inbox-update-tag-thread:root-0-0'),
              ),
            )
            .dx,
        tester
            .getTopLeft(
              find.byKey(const ValueKey<String>('inbox-source-thread:root')),
            )
            .dx,
      );
      expect(find.byType(Card), findsNWidgets(5));
      expect(find.byType(MattermostMarkdown), findsNWidgets(5));
      expect(
        tester
            .widgetList<MattermostMarkdown>(find.byType(MattermostMarkdown))
            .map((MattermostMarkdown markdown) => markdown.data),
        contains('**latest DM**'),
      );
      expect(
        find.byKey(const ValueKey<String>('inbox-update-tag-thread:root-0-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('inbox-update-tag-direct:dm:dm-1-0-0'),
        ),
        findsOneWidget,
      );
      final Finder threadCount = find.byKey(
        const ValueKey<String>('inbox-update-tag-thread:root-0-0'),
      );
      final Finder threadTimestamp = find.byKey(
        const ValueKey<String>('inbox-update-trailing-tag-thread:root-0-0'),
      );
      expect(
        find
            .ancestor(of: threadCount, matching: find.byType(Wrap))
            .evaluate()
            .single,
        same(
          find
              .ancestor(of: threadTimestamp, matching: find.byType(Wrap))
              .evaluate()
              .single,
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('unread-post:mention')),
        findsNothing,
      );
      expect(
        tester
            .widget<DecoratedBox>(
              find.descendant(
                of: find.byKey(
                  const ValueKey<String>('inbox-update-tag-thread:root-1-0'),
                ),
                matching: find.byType(DecoratedBox),
              ),
            )
            .decoration,
        isA<BoxDecoration>().having(
          (BoxDecoration decoration) => decoration.color,
          'tag background',
          isNotNull,
        ),
      );
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text(InboxStrings.read), findsNWidgets(5));
      expect(find.text(InboxStrings.postpone), findsNWidgets(5));

      final List<String> newestFirst = <String>[
        'direct:dm:dm-1',
        'thread:root',
        'post:group',
        'post:mention',
        'post:channel',
      ];
      final List<double> itemTops = newestFirst
          .map(
            (String key) => tester
                .getTopLeft(find.byKey(ValueKey<String>('inbox-item-$key')))
                .dy,
          )
          .toList();
      expect(itemTops, orderedEquals(itemTops.toList()..sort()));

      final Rect cardRect = tester.getRect(
        find.ancestor(
          of: find.byKey(const ValueKey<String>('inbox-item-post:mention')),
          matching: find.byType(Card),
        ),
      );
      final Finder read = find.byKey(
        const ValueKey<String>('read-post:mention'),
      );
      final Finder postpone = find.byKey(
        const ValueKey<String>('postpone-post:mention'),
      );
      expect(cardRect.contains(tester.getCenter(read)), isTrue);
      expect(cardRect.contains(tester.getCenter(postpone)), isTrue);
      expect(
        tester
            .widget<Card>(find.ancestor(of: read, matching: find.byType(Card)))
            .elevation,
        0,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('inbox-item-post:mention')),
      );
      expect(opened, same(items[1]));
    },
  );

  testWidgets('shows exact message counts on both Inbox tabs', (
    WidgetTester tester,
  ) async {
    final List<InboxItem> items = _items();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(_session),
          inboxRepositoryProvider.overrideWithValue(
            _InboxRepository(
              InboxSnapshot(
                newItems: items,
                postponedItems: <InboxItem>[items.first, items.last],
              ),
            ),
          ),
          postponedRepositoryProvider.overrideWithValue(
            const _PostponedRepository(),
          ),
        ],
        child: MaterialApp(home: InboxPage(onOpenItem: (_) {})),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('inbox-new-count')))
          .data,
      '6',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('inbox-postponed-count')),
          )
          .data,
      '3',
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey<String>('inbox-new-count')))
          .left,
      greaterThan(tester.getRect(find.text(InboxStrings.newItems)).right),
    );
  });

  testWidgets('uses only the channel name for non-person channel triggers', (
    WidgetTester tester,
  ) async {
    final InboxPostCandidate message = _candidate(
      'keyword',
      'Keyword notification',
      reason: InboxAttentionReason.keywordMention,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(_session),
          inboxRepositoryProvider.overrideWithValue(
            _InboxRepository(
              InboxSnapshot(
                newItems: <InboxItem>[ChannelPostInboxItem(candidate: message)],
              ),
            ),
          ),
          postponedRepositoryProvider.overrideWithValue(
            const _PostponedRepository(),
          ),
        ],
        child: MaterialApp(home: InboxPage(onOpenItem: (_) {})),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Town Square'), findsOneWidget);
    expect(find.text('You mentioned in Town Square'), findsNothing);
  });

  testWidgets('hides update details for a single direct message', (
    WidgetTester tester,
  ) async {
    final InboxPostCandidate message = _candidate(
      'single-dm',
      'Only unread direct message',
      direct: true,
    );
    final InboxItem item = DirectMessageBundleInboxItem(
      channelId: 'dm',
      authorId: 'other',
      automationClass: InboxAutomationClass.person,
      messages: <InboxPostCandidate>[message],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(_session),
          inboxRepositoryProvider.overrideWithValue(
            _InboxRepository(InboxSnapshot(newItems: <InboxItem>[item])),
          ),
          postponedRepositoryProvider.overrideWithValue(
            const _PostponedRepository(),
          ),
        ],
        child: MaterialApp(home: InboxPage(onOpenItem: (_) {})),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('inbox-updates-direct:dm:single-dm')),
      findsNothing,
    );
    expect(find.text('message since'), findsNothing);
    expect(find.text('Only unread direct message'), findsOneWidget);
  });

  testWidgets('compact and expanded layouts support large text', (
    WidgetTester tester,
  ) async {
    final InboxItem item = _items().last;
    Future<void> pumpAt(Size size) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWithValue(_session),
            inboxRepositoryProvider.overrideWithValue(
              _InboxRepository(InboxSnapshot(newItems: <InboxItem>[item])),
            ),
            postponedRepositoryProvider.overrideWithValue(
              const _PostponedRepository(),
            ),
          ],
          child: MediaQuery(
            data: MediaQueryData(size: size, textScaler: TextScaler.linear(2)),
            child: MaterialApp(home: InboxPage(onOpenItem: (_) {})),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('messages since'), findsOneWidget);
    }

    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpAt(const Size(360, 900));
    final double compactWidth = tester.getSize(find.byType(Card).first).width;
    expect(compactWidth, lessThanOrEqualTo(344));

    await pumpAt(const Size(1200, 900));
    final double expandedWidth = tester.getSize(find.byType(Card).first).width;
    expect(expandedWidth, lessThanOrEqualTo(760));
    expect(expandedWidth, greaterThan(compactWidth));
  });

  testWidgets('read action marks the item without opening its row', (
    WidgetTester tester,
  ) async {
    final InboxItem mention = _items()[1];
    final _InboxRepository repository = _InboxRepository(
      InboxSnapshot(newItems: <InboxItem>[mention]),
    );
    InboxItem? opened;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(_session),
          inboxRepositoryProvider.overrideWithValue(repository),
          postponedRepositoryProvider.overrideWithValue(
            const _PostponedRepository(),
          ),
        ],
        child: MaterialApp(
          home: InboxPage(onOpenItem: (InboxItem item) => opened = item),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('read-post:mention')));
    await tester.pumpAndSettle();

    expect(repository.markedRead, same(mention));
    expect(opened, isNull);
    expect(find.text('No new messages'), findsOneWidget);
  });

  testWidgets('postpone and remove actions update the postponed preference', (
    WidgetTester tester,
  ) async {
    final InboxItem item = ChannelPostInboxItem(
      candidate: _candidate('later', 'Review later'),
    );
    final _RecordingPostponedRepository postponed =
        _RecordingPostponedRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(_session),
          inboxRepositoryProvider.overrideWithValue(
            _InboxRepository(InboxSnapshot(newItems: <InboxItem>[item])),
          ),
          postponedRepositoryProvider.overrideWithValue(postponed),
        ],
        child: MaterialApp(home: InboxPage(onOpenItem: (_) {})),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('postpone-post:later')));
    await tester.pumpAndSettle();

    expect(postponed.saved.single.postId, 'later');
    expect(find.text(InboxStrings.emptyNew), findsOneWidget);

    await tester.tap(find.text(InboxStrings.postponed));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('remove-post:later')));
    await tester.pumpAndSettle();

    expect(postponed.removed.single.postId, 'later');
    expect(find.text(InboxStrings.emptyPostponed), findsOneWidget);
  });
}

final AuthSession _session = AuthSession(
  serverUrl: Uri.parse('https://chat.example.test'),
  userId: 'me',
  username: 'me',
);

List<InboxItem> _items() {
  final InboxPostCandidate channel = _candidate(
    'channel',
    'Channel notification',
    reason: InboxAttentionReason.allMessagesSubscription,
    sentAt: DateTime.utc(2026, 9),
  );
  final InboxPostCandidate mention = _candidate(
    'mention',
    'Please read **this**',
    sentAt: DateTime.utc(2026, 9, 2),
  );
  final InboxPostCandidate group = _candidate(
    'group',
    '@dev-team please review',
    reason: InboxAttentionReason.groupMention,
    groupMentionHandle: '@dev-team',
    sentAt: DateTime.utc(2026, 9, 3),
  );
  final InboxPostCandidate firstDm = _candidate(
    'dm-1',
    'first DM',
    direct: true,
    sentAt: DateTime.utc(2026, 9, 4),
  );
  final InboxPostCandidate secondDm = _candidate(
    'dm-2',
    '**latest DM**',
    direct: true,
    sentAt: DateTime.utc(2026, 9, 5),
  );
  return <InboxItem>[
    ChannelPostInboxItem(candidate: channel),
    ChannelPostInboxItem(candidate: mention),
    ThreadInboxItem(
      thread: FollowedThread(
        root: _post('root', 'thread root', sentAt: DateTime.utc(2026, 9, 3)),
        replyCount: 5,
        lastReplyAt: DateTime.utc(2026, 9, 4),
        lastViewedAt: DateTime.utc(2026, 9, 3),
        unreadReplies: 3,
        unreadMentions: 1,
      ),
      channel: _channel(),
      teamId: 'team',
      unreadMentionDetails: InboxThreadMentionDetails(
        mentionsCurrentUser: true,
        groupMentionHandles: const <String>['@dev-team'],
      ),
    ),
    ChannelPostInboxItem(candidate: group),
    DirectMessageBundleInboxItem(
      channelId: 'dm',
      authorId: 'other',
      automationClass: InboxAutomationClass.person,
      messages: <InboxPostCandidate>[firstDm, secondDm],
    ),
  ];
}

InboxPostCandidate _candidate(
  String id,
  String message, {
  bool direct = false,
  InboxAttentionReason reason = InboxAttentionReason.directMention,
  String? groupMentionHandle,
  DateTime? sentAt,
}) => InboxPostCandidate(
  post: _post(id, message, direct: direct, sentAt: sentAt),
  channel: _channel(direct: direct),
  reason: direct ? InboxAttentionReason.allMessagesSubscription : reason,
  groupMentionHandle: groupMentionHandle,
);

Post _post(
  String id,
  String message, {
  bool direct = false,
  DateTime? sentAt,
}) => Post(
  id: id,
  channelId: direct ? 'dm' : 'channel',
  author: const PostAuthor(id: 'other', displayName: 'Other'),
  sentAt: sentAt ?? DateTime.utc(2026, 9, 4),
  message: message,
);

SidebarChannel _channel({bool direct = false}) => SidebarChannel(
  id: direct ? 'dm' : 'channel',
  teamId: 'team',
  name: direct ? 'dm' : 'channel',
  displayName: direct ? 'Other' : 'Town Square',
  kind: direct ? ChannelKind.directMessage : ChannelKind.publicChannel,
);

final class _InboxRepository extends InboxRepository {
  _InboxRepository(
    this.snapshot, {
    this.realtime = const Stream<InboxRealtimeEvent>.empty(),
  });

  final InboxSnapshot snapshot;
  final Stream<InboxRealtimeEvent> realtime;
  InboxItem? markedRead;

  @override
  Future<InboxSnapshot> load({required AuthSession session}) async => snapshot;

  @override
  Stream<InboxRealtimeEvent> watch({required AuthSession session}) => realtime;

  @override
  Future<void> markRead({
    required AuthSession session,
    required InboxItem item,
  }) async {
    markedRead = item;
  }
}

final class _SequencedInboxRepository extends InboxRepository {
  _SequencedInboxRepository(this.results, {required this.counters});

  final List<Future<InboxSnapshot> Function()> results;
  final InboxCounters counters;
  var loadCalls = 0;

  @override
  Future<InboxCounters> loadCounters({required AuthSession session}) async =>
      counters;

  @override
  Future<InboxSnapshot> load({required AuthSession session}) {
    final Future<InboxSnapshot> Function() result = results[loadCalls];
    loadCalls++;
    return result();
  }

  @override
  Future<void> markRead({
    required AuthSession session,
    required InboxItem item,
  }) async {}
}

final class _PostponedRepository extends PostponedRepository {
  const _PostponedRepository();

  @override
  Future<PostponedReferencesSnapshot> load({
    required AuthSession session,
  }) async => PostponedReferencesSnapshot(const <PostponedReference>[]);

  @override
  Future<void> remove({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {}

  @override
  Future<void> save({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {}
}

final class _RecordingPostponedRepository extends PostponedRepository {
  final List<PostponedReference> saved = <PostponedReference>[];
  final List<PostponedReference> removed = <PostponedReference>[];

  @override
  Future<PostponedReferencesSnapshot> load({
    required AuthSession session,
  }) async => PostponedReferencesSnapshot(const <PostponedReference>[]);

  @override
  Future<void> remove({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async => removed.addAll(references);

  @override
  Future<void> save({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async => saved.addAll(references);
}
