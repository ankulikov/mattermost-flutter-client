import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_page.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_strings.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
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
      expect(find.text('2 messages'), findsOneWidget);
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
    expect(find.text('1 message'), findsNothing);
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
}

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
}) => InboxPostCandidate(
  post: _post(id, message, direct: direct),
  channel: _channel(direct: direct),
  reason: direct
      ? InboxAttentionReason.allMessagesSubscription
      : InboxAttentionReason.directMention,
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
