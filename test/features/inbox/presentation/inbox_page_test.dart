import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_completeness.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/classify_inbox_section.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_page.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_strings.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_breakpoints.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  testWidgets('shows red and green realtime connection indicators', (
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
    'renders sectioned list rows with icon actions and opens the tapped row',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
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

      expect(find.text('Mentions'), findsOneWidget);
      expect(find.text('Bots & integrations'), findsOneWidget);
      expect(find.text('Direct Messages'), findsOneWidget);
      expect(find.text('Threads'), findsOneWidget);
      expect(find.text('2 messages'), findsNWidgets(2));
      expect(find.text('first DM'), findsNothing);
      expect(find.text('second DM'), findsNothing);
      expect(find.byType(Card), findsNothing);
      expect(find.text('Open'), findsNothing);
      expect(find.byTooltip('Mark as read'), findsNWidgets(4));
      expect(find.byTooltip('Postpone'), findsNWidgets(4));
      expect(find.byIcon(Icons.done), findsNWidgets(4));
      expect(find.byIcon(Icons.schedule), findsNWidgets(4));

      await tester.tap(
        find.byKey(const ValueKey<String>('inbox-item-post:mention')),
      );
      expect(opened, same(items.first));
    },
  );

  testWidgets(
    'provides labelled 48dp actions and keyboard access to an Inbox row',
    (WidgetTester tester) async {
      final InboxItem item = _items().first;
      InboxItem? opened;
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
          child: MaterialApp(
            home: InboxPage(onOpenItem: (InboxItem value) => opened = value),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder read = find.byKey(
        const ValueKey<String>('read-post:mention'),
      );
      final Finder postpone = find.byKey(
        const ValueKey<String>('postpone-post:mention'),
      );
      expect(find.bySemanticsLabel(InboxStrings.openSettings), findsOneWidget);
      expect(find.bySemanticsLabel(InboxStrings.refresh), findsOneWidget);
      expect(
        find.bySemanticsLabel(InboxStrings.itemSemantics('Other', 'mention')),
        findsOneWidget,
      );
      expect(tester.getSize(read).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(postpone).height, greaterThanOrEqualTo(48));

      for (var attempt = 0; attempt < 10; attempt++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        if (FocusManager.instance.primaryFocus?.debugLabel ==
            'inbox-row-post:mention') {
          break;
        }
      }
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'inbox-row-post:mention',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(opened, same(item));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isNotNull);
    },
  );

  testWidgets(
    'labels ordinary channel posts as All activity and counts represented messages',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final InboxPostCandidate mention = _candidate('mention', 'Mention');
      final InboxPostCandidate ordinary = _candidate(
        'ordinary',
        'Ordinary activity',
        reason: InboxAttentionReason.allMessagesSubscription,
      );
      final InboxPostCandidate firstDm = _candidate(
        'dm-one',
        'First DM',
        direct: true,
      );
      final InboxPostCandidate secondDm = _candidate(
        'dm-two',
        'Second DM',
        direct: true,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWithValue(_session),
            inboxRepositoryProvider.overrideWithValue(
              _InboxRepository(
                InboxSnapshot(
                  newItems: <InboxItem>[
                    ChannelPostInboxItem(candidate: mention),
                    ChannelPostInboxItem(candidate: ordinary),
                    DirectMessageBundleInboxItem(
                      channelId: 'dm',
                      authorId: 'other',
                      automationClass: InboxAutomationClass.person,
                      messages: <InboxPostCandidate>[firstDm, secondDm],
                    ),
                  ],
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

      expect(find.text(InboxStrings.mentions), findsOneWidget);
      expect(find.text(InboxStrings.allActivity), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('inbox-section-mentions-count')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const ValueKey<String>('inbox-section-mentions-count'),
              ),
            )
            .data,
        '1 message',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const ValueKey<String>('inbox-section-allActivity-count'),
              ),
            )
            .data,
        '1 message',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const ValueKey<String>('inbox-section-directMessages-count'),
              ),
            )
            .data,
        '2 messages',
      );
      expect(find.text('Ordinary activity'), findsOneWidget);
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
                postponedItems: <InboxItem>[items.first, items[2]],
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
      '5',
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

  testWidgets('shows the message text for a single direct message', (
    WidgetTester tester,
  ) async {
    final InboxPostCandidate message = _candidate(
      'only-dm',
      'Only direct message',
      direct: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(_session),
          inboxRepositoryProvider.overrideWithValue(
            _InboxRepository(
              InboxSnapshot(
                newItems: <InboxItem>[
                  DirectMessageBundleInboxItem(
                    channelId: 'dm',
                    authorId: 'other',
                    automationClass: InboxAutomationClass.person,
                    messages: <InboxPostCandidate>[message],
                  ),
                ],
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

    expect(find.text('Only direct message'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('inbox-section-directMessages-count')),
      findsOneWidget,
    );
  });

  testWidgets('read action marks the item without opening its row', (
    WidgetTester tester,
  ) async {
    final InboxItem mention = _items().first;
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

  testWidgets(
    'renders an unavailable postponed reference without content and removes it',
    (WidgetTester tester) async {
      final PostponedReference reference = PostponedReference(
        postId: 'private-post-id',
        kind: PostponedReferenceKind.thread,
        addedAt: DateTime.utc(2026, 9, 1),
        targetPostId: 'private-reply-id',
      );
      final _RecordingPostponedRepository postponed =
          _RecordingPostponedRepository();
      InboxItem? opened;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWithValue(_session),
            inboxRepositoryProvider.overrideWithValue(
              _InboxRepository(
                InboxSnapshot(
                  postponedItems: <InboxItem>[
                    UnavailablePostponedInboxItem(reference: reference),
                  ],
                ),
              ),
            ),
            postponedRepositoryProvider.overrideWithValue(postponed),
          ],
          child: MaterialApp(
            home: InboxPage(onOpenItem: (InboxItem item) => opened = item),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(InboxStrings.postponed));
      await tester.pumpAndSettle();

      final String key = 'postponed-unavailable:thread:private-post-id';
      expect(find.text(InboxStrings.unavailablePostponedTitle), findsOneWidget);
      expect(find.text(InboxStrings.unavailablePostponedBody), findsOneWidget);
      expect(find.text('private-post-id'), findsNothing);
      expect(find.text('private-reply-id'), findsNothing);
      expect(
        find.byKey(ValueKey<String>('unavailable-postponed-$key')),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey<String>('read-$key')), findsNothing);
      expect(find.byKey(ValueKey<String>('postpone-$key')), findsNothing);
      expect(find.byKey(ValueKey<String>('remove-$key')), findsOneWidget);

      expect(
        find.bySemanticsLabel(InboxStrings.unavailablePostponedSemantics),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ValueKey<String>('inbox-item-$key')));
      expect(opened, isNull);
      await tester.tap(find.byKey(ValueKey<String>('remove-$key')));
      await tester.pumpAndSettle();

      expect(postponed.removed, <PostponedReference>[reference]);
      expect(find.text(InboxStrings.emptyPostponed), findsOneWidget);
    },
  );

  testWidgets('shows exact, approximate, and truncated coverage accessibly', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      for (final InboxCompleteness completeness in InboxCompleteness.values) {
        await tester.pumpWidget(
          _inboxPage(
            _InboxRepository(InboxSnapshot(completeness: completeness)),
          ),
        );
        await tester.pump();
        await tester.pump();

        final String label = InboxStrings.completeness(completeness);
        final Finder status = find.byKey(
          ValueKey<String>('inbox-completeness-${completeness.name}'),
        );
        expect(status, findsOneWidget);
        expect(find.text(label), findsOneWidget);
        expect(tester.getSemantics(status).label, contains(label));
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('keeps data and exposes independent scoped source retries', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final InboxItem item = _items().first;
    final _ScopedRetryInboxRepository repository = _ScopedRetryInboxRepository(
      InboxSnapshot(
        newItems: <InboxItem>[item],
        completeness: InboxCompleteness.truncated,
        sourceFailures: <InboxSourceFailure>{
          const InboxSourceFailure(scope: InboxSourceScope.followedThreads),
          const InboxSourceFailure(scope: InboxSourceScope.postponed),
        },
      ),
      InboxSnapshot(newItems: <InboxItem>[item]),
    );
    await tester.pumpWidget(_inboxPage(repository));
    await tester.pumpAndSettle();

    expect(find.text('mention'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('inbox-source-failure-followedThreads'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('inbox-source-failure-postponed')),
      findsOneWidget,
    );
    expect(find.text(InboxStrings.followedThreadsSourceFailed), findsOneWidget);
    expect(find.text(InboxStrings.postponedSourceFailed), findsOneWidget);

    final Finder postponedRetry = find.descendant(
      of: find.byKey(const ValueKey<String>('inbox-source-failure-postponed')),
      matching: find.widgetWithText(TextButton, InboxStrings.retry),
    );
    expect(tester.getSize(postponedRetry).height, greaterThanOrEqualTo(48));
    await tester.tap(postponedRetry);
    await tester.pumpAndSettle();

    expect(repository.retriedScopes, <InboxSourceScope>[
      InboxSourceScope.postponed,
    ]);
    expect(find.text('mention'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('inbox-source-failure-postponed')),
      findsNothing,
    );
  });

  testWidgets(
    'retries an initial load failure and a refresh failure without hiding data',
    (WidgetTester tester) async {
      final InboxItem initialItem = _items().first;
      final InboxItem refreshedItem = _items()[1];
      final _SequenceInboxRepository repository = _SequenceInboxRepository(
        <Future<InboxSnapshot> Function()>[
          () => Future<InboxSnapshot>.error(StateError('offline')),
          () async => InboxSnapshot(newItems: <InboxItem>[initialItem]),
          () => Future<InboxSnapshot>.error(StateError('offline')),
          () async => InboxSnapshot(newItems: <InboxItem>[refreshedItem]),
        ],
      );
      await tester.pumpWidget(_inboxPage(repository));
      await tester.pumpAndSettle();

      expect(find.text(InboxStrings.loadFailed), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, InboxStrings.retry));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('mention'), findsOneWidget);

      await tester.tap(find.byTooltip(InboxStrings.refresh));
      await tester.pumpAndSettle();
      expect(find.text('mention'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('inbox-refresh-failure')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('inbox-refresh-failure')),
          matching: find.widgetWithText(TextButton, InboxStrings.retry),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('bot message'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('inbox-refresh-failure')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'status messages adapt to wide layout, dark theme, and text scale',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final InboxSnapshot snapshot = InboxSnapshot(
        completeness: InboxCompleteness.approximateMentions,
        sourceFailures: <InboxSourceFailure>{
          const InboxSourceFailure(scope: InboxSourceScope.unreadChannelPosts),
        },
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: ProviderScope(
              overrides: [
                authSessionProvider.overrideWithValue(_session),
                inboxRepositoryProvider.overrideWithValue(
                  _InboxRepository(snapshot),
                ),
                postponedRepositoryProvider.overrideWithValue(
                  const _PostponedRepository(),
                ),
              ],
              child: InboxPage(onOpenItem: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(InboxStrings.completenessApproximateMentions),
        findsOneWidget,
      );
      expect(
        find.text(InboxStrings.unreadChannelPostsSourceFailed),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('renders all five Inbox sections with semantic message counts', (
    WidgetTester tester,
  ) async {
    final InboxPostCandidate mention = _candidate('mention', 'Mention');
    final InboxPostCandidate ordinary = _candidate(
      'ordinary',
      'All activity post',
      reason: InboxAttentionReason.allMessagesSubscription,
    );
    final InboxPostCandidate bot = _candidate('bot', 'Bot post', fromBot: true);
    final InboxPostCandidate direct = _candidate(
      'direct',
      'Direct post',
      direct: true,
    );
    final ThreadInboxItem thread = _items().last as ThreadInboxItem;
    final InboxSnapshot snapshot = InboxSnapshot(
      newItems: <InboxItem>[
        ChannelPostInboxItem(candidate: mention),
        ChannelPostInboxItem(candidate: ordinary),
        ChannelPostInboxItem(candidate: bot),
        DirectMessageBundleInboxItem(
          channelId: direct.channel.id,
          authorId: direct.post.author.id,
          automationClass: InboxAutomationClass.person,
          messages: <InboxPostCandidate>[direct],
        ),
        thread,
      ],
    );
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_inboxPage(_InboxRepository(snapshot)));
      await tester.pumpAndSettle();

      for (final (InboxSection section, String label)
          in <(InboxSection, String)>[
            (InboxSection.mentions, InboxStrings.mentions),
            (InboxSection.allActivity, InboxStrings.allActivity),
            (InboxSection.botsAndIntegrations, InboxStrings.bots),
            (InboxSection.directMessages, InboxStrings.directMessages),
            (InboxSection.threads, InboxStrings.threads),
          ]) {
        final Finder header = find.byKey(
          ValueKey<String>('inbox-section-${section.name}-count'),
        );
        expect(header, findsOneWidget);
        expect(find.text(label), findsOneWidget);
        expect(
          find.bySemanticsLabel(InboxStrings.sectionWithMessageCount(label, 1)),
          findsOneWidget,
        );
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'keeps Inbox usable at compact, medium, and expanded breakpoint edges',
    (WidgetTester tester) async {
      final InboxSnapshot snapshot = InboxSnapshot(
        newItems: <InboxItem>[_items().first],
        completeness: InboxCompleteness.truncated,
      );
      final List<double> widths = <double>[
        AppBreakpoints.compact - 1,
        AppBreakpoints.compact,
        AppBreakpoints.expanded - 1,
        AppBreakpoints.expanded,
      ];
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final ProviderContainer container = await _inboxContainer(
        _InboxRepository(snapshot),
      );
      addTearDown(container.dispose);

      for (final double width in widths) {
        await tester.binding.setSurfaceSize(Size(width, 900));
        await tester.pumpWidget(_inboxPageFromContainer(container));
        await tester.pump();

        expect(
          find.byKey(const ValueKey<String>('inbox-new-count')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('inbox-completeness-truncated')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: 'width: $width');
      }
    },
  );
}

Widget _inboxPage(InboxRepository repository) => ProviderScope(
  key: ValueKey<InboxRepository>(repository),
  overrides: [
    authSessionProvider.overrideWithValue(_session),
    inboxRepositoryProvider.overrideWithValue(repository),
    postponedRepositoryProvider.overrideWithValue(const _PostponedRepository()),
  ],
  child: MaterialApp(home: InboxPage(onOpenItem: (_) {})),
);

Future<ProviderContainer> _inboxContainer(InboxRepository repository) async {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      authSessionProvider.overrideWithValue(_session),
      inboxRepositoryProvider.overrideWithValue(repository),
      postponedRepositoryProvider.overrideWithValue(
        const _PostponedRepository(),
      ),
    ],
  );
  await container.read(inboxSessionProvider.future);
  return container;
}

Widget _inboxPageFromContainer(ProviderContainer container) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: InboxPage(onOpenItem: (_) {})),
    );

final AuthSession _session = AuthSession(
  serverUrl: Uri.parse('https://chat.example.test'),
  userId: 'me',
  username: 'me',
);

List<InboxItem> _items() {
  final InboxPostCandidate mention = _candidate('mention', 'mention');
  final InboxPostCandidate bot = _candidate(
    'bot',
    'bot message',
    fromBot: true,
  );
  final InboxPostCandidate firstDm = _candidate(
    'dm-1',
    'first DM',
    direct: true,
  );
  final InboxPostCandidate secondDm = _candidate(
    'dm-2',
    'second DM',
    direct: true,
  );
  return <InboxItem>[
    ChannelPostInboxItem(candidate: mention),
    ChannelPostInboxItem(candidate: bot),
    DirectMessageBundleInboxItem(
      channelId: 'dm',
      authorId: 'other',
      automationClass: InboxAutomationClass.person,
      messages: <InboxPostCandidate>[firstDm, secondDm],
    ),
    ThreadInboxItem(
      thread: FollowedThread(
        root: _post('root', 'thread root'),
        replyCount: 1,
        lastReplyAt: DateTime.utc(2026, 9, 4),
        lastViewedAt: DateTime.utc(2026, 9, 3),
        unreadReplies: 1,
        unreadMentions: 1,
      ),
      channel: _channel(),
      teamId: 'team',
    ),
  ];
}

InboxPostCandidate _candidate(
  String id,
  String message, {
  bool direct = false,
  bool fromBot = false,
  InboxAttentionReason? reason,
}) => InboxPostCandidate(
  post: _post(id, message, direct: direct),
  channel: _channel(direct: direct),
  reason:
      reason ??
      (direct
          ? InboxAttentionReason.allMessagesSubscription
          : InboxAttentionReason.directMention),
  isFromBot: fromBot,
);

Post _post(String id, String message, {bool direct = false}) => Post(
  id: id,
  channelId: direct ? 'dm' : 'channel',
  author: const PostAuthor(id: 'other', displayName: 'Other'),
  sentAt: DateTime.utc(2026, 9, 4),
  message: message,
);

SidebarChannel _channel({bool direct = false}) => SidebarChannel(
  id: direct ? 'dm' : 'channel',
  teamId: 'team',
  name: direct ? 'dm' : 'channel',
  displayName: direct ? 'DM' : 'Channel',
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

final class _ScopedRetryInboxRepository extends InboxRepository {
  _ScopedRetryInboxRepository(this._initial, this._retried);

  final InboxSnapshot _initial;
  final InboxSnapshot _retried;
  final List<InboxSourceScope> retriedScopes = <InboxSourceScope>[];

  @override
  Future<InboxSnapshot> load({required AuthSession session}) async => _initial;

  @override
  Future<InboxSnapshot> reloadSource({
    required AuthSession session,
    required InboxSnapshot current,
    required InboxSourceScope scope,
  }) async {
    retriedScopes.add(scope);
    return _retried;
  }

  @override
  Future<void> markRead({
    required AuthSession session,
    required InboxItem item,
  }) async {}
}

final class _SequenceInboxRepository extends InboxRepository {
  _SequenceInboxRepository(this._results);

  final List<Future<InboxSnapshot> Function()> _results;
  var _index = 0;

  @override
  Future<InboxSnapshot> load({required AuthSession session}) =>
      _results[_index++]();

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
  List<PostponedReference> removed = <PostponedReference>[];

  @override
  Future<PostponedReferencesSnapshot> load({
    required AuthSession session,
  }) async => PostponedReferencesSnapshot(const <PostponedReference>[]);

  @override
  Future<void> remove({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {
    removed = List<PostponedReference>.of(references);
  }

  @override
  Future<void> save({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {}
}
