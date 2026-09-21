import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/app/app.dart';
import 'package:mattermost_flutter/src/app/router.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/authentication_methods.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/message_thread.dart';
import 'package:mattermost_flutter/src/domain/models/post_navigation.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/auth_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/channel_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/features/profile/domain/models/current_user_profile.dart';
import 'package:mattermost_flutter/src/features/profile/domain/repositories/current_user_profile_repository.dart';
import 'package:mattermost_flutter/src/ui/auth/auth_strings.dart';
import 'package:mattermost_flutter/src/ui/channels/channel_sidebar_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';
import 'package:mattermost_flutter/src/ui/shell/shell_page.dart';
import 'package:mattermost_flutter/src/ui/threads/widgets/thread_pane.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';
import 'support/fake_user_repository.dart';

void main() {
  Future<void> selectInbox(WidgetTester tester) async {
    final Finder rail = find.byKey(
      const ValueKey<String>('shell-navigation-rail'),
    );
    final Finder navigation = rail.evaluate().isNotEmpty
        ? rail
        : find.byKey(const ValueKey<String>('shell-bottom-navigation'));
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Inbox')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('uses a drawer on compact screens', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedOutRepository()),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.drawer, isA<Drawer>());
    expect(find.text('Mattermost'), findsOneWidget);
  });

  testWidgets('switches layout on both sides of shared breakpoints', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(699, 800));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('compact-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('shell-bottom-navigation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('shell-navigation-rail')),
      findsNothing,
    );

    await tester.binding.setSurfaceSize(const Size(700, 800));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('medium-layout')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('shell-navigation-rail')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('shell-bottom-navigation')),
      findsNothing,
    );

    await tester.binding.setSurfaceSize(const Size(1119, 800));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('medium-layout')), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1120, 800));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('expanded-layout')),
      findsOneWidget,
    );
  });

  testWidgets('opens Profile from the bottom of the rail and logs out', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          currentUserProfileRepositoryProvider.overrideWithValue(
            _CurrentProfileRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    final Finder profileDestination = find.byKey(
      const ValueKey<String>('shell-profile-destination'),
    );
    expect(profileDestination, findsOneWidget);
    expect(
      tester.getCenter(profileDestination).dy,
      greaterThan(tester.getCenter(find.text('Inbox')).dy),
    );

    await tester.tap(profileDestination);
    await tester.pumpAndSettle();
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('profile-logout')),
      findsOneWidget,
    );

    final Finder logout = find.byKey(const ValueKey<String>('profile-logout'));
    final Finder profileScrollable = find.descendant(
      of: find.byKey(const ValueKey<String>('profile-scroll-view')),
      matching: find.byType(Scrollable),
    );
    await tester.drag(profileScrollable, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(logout);
    await tester.pumpAndSettle();
    expect(find.text(AuthStrings.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens Profile from the rightmost compact destination', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          currentUserProfileRepositoryProvider.overrideWithValue(
            _CurrentProfileRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    final NavigationBar navigation = tester.widget<NavigationBar>(
      find.byKey(const ValueKey<String>('shell-bottom-navigation')),
    );
    expect(navigation.destinations, hasLength(4));
    expect(
      (navigation.destinations.last as NavigationDestination).label,
      'Profile',
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('shell-bottom-navigation')),
        matching: find.text('Profile'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('profile-logout')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('replaces the channel pane with Inbox on a wide screen', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(
            const _DelayedPostRepository(delay: Duration.zero),
          ),
          inboxRepositoryProvider.overrideWithValue(_InboxTestRepository()),
          postponedRepositoryProvider.overrideWithValue(
            _PostponedTestRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    final Container inboxIndicator = tester.widget<Container>(
      find.byKey(const ValueKey<String>('inbox-navigation-indicator')),
    );
    expect(inboxIndicator.decoration, isA<BoxDecoration>());

    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();
    expect(find.text('Message for town-square'), findsOneWidget);

    await selectInbox(tester);

    expect(
      find.byKey(const ValueKey<String>('channels-side-pane')),
      findsNothing,
    );
    final Finder inboxPane = find.byKey(
      const ValueKey<String>('inbox-thread-list-pane'),
    );
    expect(inboxPane, findsOneWidget);
    expect(tester.getSize(inboxPane).width, 380);
    expect(find.text('Inbox message'), findsOneWidget);
    expect(find.text('Message for town-square'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adds the adjacent Inbox workspace at the compact breakpoint', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(699, 800));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          inboxRepositoryProvider.overrideWithValue(_InboxTestRepository()),
          postponedRepositoryProvider.overrideWithValue(
            _PostponedTestRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await selectInbox(tester);

    expect(
      find.byKey(const ValueKey<String>('inbox-thread-host-narrow')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('inbox-thread-host-wide')),
      findsNothing,
    );

    await tester.binding.setSurfaceSize(const Size(700, 800));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('inbox-thread-host-narrow')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('inbox-thread-host-wide')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stacks compact panes and returns to bottom navigation', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(
            const _DelayedPostRepository(delay: Duration.zero),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Town Square'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('shell-bottom-navigation')),
      findsOneWidget,
    );

    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();

    expect(find.text('Message for town-square'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('shell-bottom-navigation')),
      findsNothing,
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Town Square'), findsOneWidget);
    expect(find.text('Message for town-square'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('shell-bottom-navigation')),
      findsOneWidget,
    );
  });

  testWidgets('shows categorized channels and dialogs when signed in', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Example team'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Town Square'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('channels-side-pane')),
        matching: find.text('Inbox'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'filters loaded channels and dialogs by display name in their categories',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_SignedInRepository()),
            channelRepositoryProvider.overrideWithValue(
              _SearchSidebarRepository(),
            ),
          ],
          child: const MaterialApp(home: BootstrapPage()),
        ),
      );
      await tester.pumpAndSettle();

      final Finder search = find.byKey(
        const ValueKey<String>('channel-search-field'),
      );
      expect(search, findsOneWidget);
      expect(tester.getSize(search).height, 48);
      expect(find.text('Public channels'), findsOneWidget);
      expect(find.text('Town Square'), findsNothing);
      expect(find.text('Direct messages'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);

      await tester.tap(search);
      await tester.pump();
      expect(tester.widget<TextField>(search).focusNode?.hasFocus, isTrue);

      await tester.enterText(search, 'town');
      await tester.pump();
      expect(find.text('Public channels'), findsOneWidget);
      expect(find.text('Town Square'), findsOneWidget);
      expect(find.text('Direct messages'), findsNothing);
      expect(find.text('Ada Lovelace'), findsNothing);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(tester.widget<TextField>(search).focusNode?.hasFocus, isFalse);
      expect(find.text('Town Square'), findsOneWidget);

      await tester.tap(find.byTooltip(ChannelSidebarStrings.clearSearch));
      await tester.pump();
      expect(find.text('Public channels'), findsOneWidget);
      expect(find.text('Town Square'), findsNothing);
      expect(find.text('Direct messages'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.byTooltip(ChannelSidebarStrings.clearSearch), findsNothing);

      await tester.enterText(search, 'ada');
      await tester.pump();
      expect(find.text('Public channels'), findsNothing);
      expect(find.text('Direct messages'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('Grace Hopper'), findsNothing);

      await tester.enterText(search, 'me__ada');
      await tester.pump();
      expect(find.text(ChannelSidebarStrings.noSearchResults), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows Inbox tabs and moves an item to Postponed', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          inboxRepositoryProvider.overrideWithValue(_InboxTestRepository()),
          postponedRepositoryProvider.overrideWithValue(
            _PostponedTestRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    await selectInbox(tester);

    expect(find.text('Inbox'), findsWidgets);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Postponed'), findsOneWidget);
    expect(find.text('Inbox message'), findsOneWidget);
    expect(find.byTooltip('Postpone'), findsOneWidget);

    await tester.tap(find.byTooltip('Postpone'));
    await tester.pumpAndSettle();
    expect(find.text('No new messages'), findsOneWidget);

    await tester.tap(find.text('Postponed'));
    await tester.pumpAndSettle();
    expect(find.text('Inbox message'), findsOneWidget);
    expect(find.byTooltip('Remove'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('No postponed messages'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an Inbox notification while Channels stays open', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _RealtimeInboxTestRepository inbox = _RealtimeInboxTestRepository();
    addTearDown(inbox.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          inboxRepositoryProvider.overrideWithValue(inbox),
          postponedRepositoryProvider.overrideWithValue(
            _PostponedTestRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Town Square'), findsOneWidget);
    expect(inbox.watchCalls, 1);

    inbox.addPost('realtime', 'A realtime Inbox message');
    await tester.pumpAndSettle();

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(BootstrapPage)),
    );
    expect(
      container.read(inboxProvider).value?.inAppNotification?.id,
      'realtime',
    );

    expect(
      find.byKey(const ValueKey<String>('inbox-in-app-notification')),
      findsOneWidget,
    );
    expect(
      find.text('Ada Lovelace · Town Square\nA realtime Inbox message'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('inbox-navigation-indicator')),
      findsOneWidget,
    );
    expect(find.text('Town Square'), findsOneWidget);

    await tester.tap(find.text('Open Inbox'));
    await tester.pumpAndSettle();
    expect(find.text('A realtime Inbox message'), findsOneWidget);
    expect(inbox.watchCalls, 1);
  });

  testWidgets('resume reconnects and refreshes the app-owned Inbox', (
    WidgetTester tester,
  ) async {
    final _RealtimeInboxTestRepository inbox = _RealtimeInboxTestRepository();
    addTearDown(inbox.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          inboxRepositoryProvider.overrideWithValue(inbox),
          postponedRepositoryProvider.overrideWithValue(
            _PostponedTestRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(inbox.loadCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(inbox.reconnectCalls, 1);
    expect(inbox.loadCalls, 2);
  });

  testWidgets('shows Inbox on compact width with large text', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          inboxRepositoryProvider.overrideWithValue(_InboxTestRepository()),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: BootstrapPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await selectInbox(tester);

    expect(find.text('Inbox'), findsWidgets);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Town Square'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loads mock messages after selecting a channel', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(
            const _DelayedPostRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Town Square'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Message for town-square'), findsNothing);

    await tester.pump(const Duration(milliseconds: 799));
    expect(find.text('Message for town-square'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.text('Message for town-square'), findsOneWidget);
    expect(find.text('Follow-up message 1'), findsOneWidget);
    expect(find.text('Follow-up message 2'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('reaction-👍')), findsOneWidget);
    expect(find.byType(CircleAvatar), findsOneWidget);
  });

  testWidgets('sends a text message in the selected channel', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _RecordingPostRepository sender = _RecordingPostRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(sender),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('message-input-town-square')),
      'New channel message',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('send-message-town-square')),
    );
    await tester.pumpAndSettle();

    expect(sender.channelId, 'town-square');
    expect(sender.rootPostId, isEmpty);
    expect(sender.message, 'New channel message');
    expect(sender.pendingPostId, isNotEmpty);
    expect(find.text('New channel message'), findsOneWidget);
  });

  testWidgets('sends a text reply and updates both thread and root summary', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _RecordingPostRepository sender = _RecordingPostRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(sender),
          threadRepositoryProvider.overrideWithValue(const _ThreadRepository()),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('2 replies'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(
        const ValueKey<String>('message-input-thread-town-square-post'),
      ),
      'New thread reply',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('send-message-thread-town-square-post'),
      ),
    );
    await tester.pumpAndSettle();

    expect(sender.channelId, 'town-square');
    expect(sender.rootPostId, 'town-square-post');
    expect(sender.message, 'New thread reply');
    expect(find.text('New thread reply'), findsOneWidget);
    expect(find.textContaining('3 replies'), findsWidgets);

    await tester.tap(find.byTooltip('Close thread'));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 replies'), findsOneWidget);
  });

  testWidgets('shows messages on compact width with large text', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(
            const _DelayedPostRepository(delay: Duration.zero),
          ),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: BootstrapPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();

    expect(find.text('Message for town-square'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens a root permalink in the channel and highlights it', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => appRouter.go('/'));
    final _PermalinkPostRepository posts = _PermalinkPostRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(posts),
        ],
        child: const MattermostApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.textContaining('Open linked root', findRichText: true),
    );
    await tester.pumpAndSettle();

    expect(posts.resolvedPostId, 'linked-root');
    expect(posts.aroundPostId, 'linked-root');
    expect(
      find.byKey(const ValueKey<String>('highlighted-post-linked-root')),
      findsOneWidget,
    );
    expect(find.text('Historical linked message'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Oldest message')).dy,
      lessThan(tester.getTopLeft(find.text('Older message')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Older message')).dy,
      lessThan(tester.getTopLeft(find.text('Historical linked message')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Historical linked message')).dy,
      lessThan(tester.getTopLeft(find.text('Newer message')).dy),
    );
    expect(find.byType(ThreadPane), findsNothing);
  });

  testWidgets(
    'Message clears stacked routes and opens the direct channel from Channels',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() => appRouter.go('/'));
      final _PermalinkPostRepository posts = _PermalinkPostRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_SignedInRepository()),
            channelRepositoryProvider.overrideWithValue(
              _DirectMessageSidebarRepository(),
            ),
            postRepositoryProvider.overrideWithValue(posts),
            userRepositoryProvider.overrideWithValue(FakeUserRepository()),
          ],
          child: const MattermostApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Town Square'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.textContaining('Open linked root', findRichText: true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(MessageAvatar).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Message'));
      await tester.pumpAndSettle();

      expect(appRouter.routeInformationProvider.value.uri.path, '/');
      expect(find.text('Message for direct-grace'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const PageStorageKey<String>('channel-sidebar')),
        findsOneWidget,
      );
      expect(find.text('Grace Hopper'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Message keeps Channels beside the direct channel on wide layouts',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() => appRouter.go('/'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_SignedInRepository()),
            channelRepositoryProvider.overrideWithValue(
              _DirectMessageSidebarRepository(),
            ),
            postRepositoryProvider.overrideWithValue(
              _PermalinkPostRepository(),
            ),
            userRepositoryProvider.overrideWithValue(FakeUserRepository()),
          ],
          child: const MattermostApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Town Square'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(MessageAvatar).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Message'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('channels-side-pane')),
        findsOneWidget,
      );
      expect(find.text('Message for direct-grace'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('channel-selection-surface-direct-grace'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keeps the thread root above the divider when a reply is highlighted',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() => appRouter.go('/'));
      final _PermalinkPostRepository posts = _PermalinkPostRepository(
        replyTarget: true,
        replyPostId: 'reply-1',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_SignedInRepository()),
            channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
            postRepositoryProvider.overrideWithValue(posts),
            threadRepositoryProvider.overrideWithValue(
              const _ThreadRepository(),
            ),
          ],
          child: const MattermostApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Town Square'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.textContaining('Open linked reply', findRichText: true),
      );
      await tester.pumpAndSettle();

      final Finder root = find.byKey(
        const ValueKey<String>('thread-post-town-square-post'),
      );
      final Finder divider = find.text('2 replies');
      final Finder reply = find.byKey(
        const ValueKey<String>('highlighted-thread-post-reply-1'),
      );
      expect(root, findsOneWidget);
      expect(divider, findsOneWidget);
      expect(reply, findsOneWidget);
      expect(
        tester.getTopLeft(root).dy,
        lessThan(tester.getTopLeft(divider).dy),
      );
      expect(
        tester.getTopLeft(divider).dy,
        lessThan(tester.getTopLeft(reply).dy),
      );
    },
  );

  testWidgets(
    'wide linked thread Close keeps target channel and Back restores source',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() => appRouter.go('/'));
      final _PermalinkPostRepository posts = _PermalinkPostRepository(
        replyTarget: true,
        replyPostId: 'reply-1',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_SignedInRepository()),
            channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
            postRepositoryProvider.overrideWithValue(posts),
            threadRepositoryProvider.overrideWithValue(
              const _ThreadRepository(),
            ),
          ],
          child: const MattermostApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Town Square'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.textContaining('Open linked reply', findRichText: true),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('highlighted-post-town-square-post')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('highlighted-thread-post-reply-1')),
        findsOneWidget,
      );
      expect(find.byType(ThreadPane), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(ThreadPane), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('highlighted-post-town-square-post')),
        findsOneWidget,
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Open linked reply', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(ThreadPane), findsNothing);
    },
  );

  testWidgets(
    'opens and highlights a linked reply; Back returns to its source channel',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() => appRouter.go('/'));
      final _PermalinkPostRepository posts = _PermalinkPostRepository(
        replyTarget: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_SignedInRepository()),
            channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
            postRepositoryProvider.overrideWithValue(posts),
            threadRepositoryProvider.overrideWithValue(
              const _ThreadRepository(longThread: true),
            ),
          ],
          child: const MattermostApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Town Square'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.textContaining('Open linked reply', findRichText: true),
      );
      await tester.pumpAndSettle();

      expect(posts.resolvedPostId, 'reply-20');
      expect(posts.aroundPostId, isNull);
      expect(
        find.byKey(const ValueKey<String>('highlighted-thread-post-reply-20')),
        findsOneWidget,
      );
      final CustomScrollView threadMessages = tester.widget<CustomScrollView>(
        find.byKey(
          const ValueKey<String>('thread-message-list-town-square-post'),
        ),
      );
      expect(threadMessages.controller?.position.pixels, isNot(0));
      final Rect highlightedReply = tester.getRect(
        find.byKey(const ValueKey<String>('highlighted-thread-post-reply-20')),
      );
      final Rect threadViewport = tester.getRect(
        find.byKey(
          const ValueKey<String>('thread-message-list-town-square-post'),
        ),
      );
      expect(
        highlightedReply.center.dy,
        inInclusiveRange(threadViewport.top, threadViewport.bottom),
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(ThreadPane), findsNothing);
      expect(
        find.textContaining('Open linked reply', findRichText: true),
        findsOneWidget,
      );
    },
  );

  testWidgets('opens a thread beside the channel on expanded width', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(
            const _DelayedPostRepository(delay: Duration.zero),
          ),
          threadRepositoryProvider.overrideWithValue(const _ThreadRepository()),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('2 replies'));
    await tester.pumpAndSettle();

    expect(find.text('Thread'), findsOneWidget);
    expect(find.text('Thread reply 1'), findsOneWidget);
    expect(find.text('This message was deleted'), findsOneWidget);
    expect(find.text('Deleted reply contents'), findsNothing);
    expect(find.text('Message for town-square'), findsNWidgets(2));
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('thread-town-square-post')),
          )
          .width,
      380,
    );
  });

  testWidgets('opens a channel thread without changing its initial position', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(
            const _DelayedPostRepository(delay: Duration.zero),
          ),
          threadRepositoryProvider.overrideWithValue(const _ThreadRepository()),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('2 replies'));
    await tester.pumpAndSettle();

    final ListView messages = tester.widget<ListView>(
      find.byKey(
        const ValueKey<String>('thread-message-list-town-square-post'),
      ),
    );
    expect(messages.controller?.position.pixels, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens a thread over the channel on compact width', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.padding = const FakeViewPadding(top: 72, bottom: 72);
    addTearDown(tester.view.resetPadding);
    tester.view.viewPadding = const FakeViewPadding(top: 72, bottom: 72);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(() => appRouter.go('/'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(
            const _DelayedPostRepository(delay: Duration.zero),
          ),
          threadRepositoryProvider.overrideWithValue(const _ThreadRepository()),
        ],
        child: const MattermostApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('2 replies'));
    await tester.pumpAndSettle();

    expect(find.text('Thread'), findsOneWidget);
    expect(find.text('Thread reply 1'), findsOneWidget);
    expect(find.text('Message for town-square'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(ThreadPane)).dy,
      greaterThanOrEqualTo(24),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('thread-town-square-post')),
          )
          .width,
      390,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Thread'), findsNothing);
    expect(find.text('Message for town-square'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the compact thread composer above the keyboard', (
    WidgetTester tester,
  ) async {
    const double keyboardHeight = 320;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetViewInsets);
    addTearDown(() => appRouter.go('/'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(
            const _DelayedPostRepository(delay: Duration.zero),
          ),
          threadRepositoryProvider.overrideWithValue(const _ThreadRepository()),
        ],
        child: const MattermostApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('2 replies'));
    await tester.pumpAndSettle();

    tester.view.viewInsets = FakeViewPadding(
      bottom: keyboardHeight * tester.view.devicePixelRatio,
    );
    await tester.pumpAndSettle();

    final Finder composer = find.byKey(
      const ValueKey<String>('message-composer-thread-town-square-post'),
    );
    expect(
      tester.getBottomRight(composer).dy,
      lessThanOrEqualTo(844 - keyboardHeight),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto-pages when replies leave a short root list unscrollable', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _AutoPagingPostRepository posts = _AutoPagingPostRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(posts),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();

    expect(posts.loadOlderCalls, 2);
    expect(find.text('Older root'), findsOneWidget);
  });

  testWidgets('auto-pages when a page contains no visible roots', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _AutoPagingPostRepository posts = _AutoPagingPostRepository(
      startsEmpty: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(posts),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();

    expect(posts.loadOlderCalls, 2);
    expect(find.text('Older root'), findsOneWidget);
    expect(find.textContaining('1 reply'), findsOneWidget);
  });

  testWidgets('stops viewport auto-paging after a paging failure', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _AutoPagingPostRepository posts = _AutoPagingPostRepository(
      failLoads: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(posts),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();

    expect(posts.loadOlderCalls, 1);
  });

  testWidgets('bounds viewport auto-paging and leaves a manual fallback', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _AutoPagingPostRepository posts = _AutoPagingPostRepository(
      neverCompletes: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(posts),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();

    expect(posts.loadOlderCalls, 20);
    expect(find.text('Load older messages'), findsOneWidget);
  });

  testWidgets('lazily builds channels in a large expandable category', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(
            _LargeSidebarRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Channel 0'), findsOneWidget);
    expect(find.text('Channel 199'), findsNothing);
    expect(find.byType(ListTile).evaluate().length, lessThan(30));

    await tester.tap(find.text('Large category'));
    await tester.pumpAndSettle();
    expect(find.text('Channel 0'), findsNothing);

    await tester.tap(find.text('Large category'));
    await tester.pumpAndSettle();
    expect(find.text('Channel 0'), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, lessThan(30));
  });

  testWidgets('clips the selected channel background while scrolling', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(
            _LargeSidebarRepository(),
          ),
          postRepositoryProvider.overrideWithValue(
            const _DelayedPostRepository(delay: Duration.zero),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    final Finder search = find.byKey(
      const ValueKey<String>('channel-search-field'),
    );
    final Rect searchRect = tester.getRect(search);

    await tester.tap(find.text('Channel 0'));
    await tester.pumpAndSettle();

    final Finder selectionSurface = find.byKey(
      const ValueKey<String>('channel-selection-surface-channel-0'),
      skipOffstage: false,
    );
    final Material material = tester.widget<Material>(selectionSurface);
    expect(
      material.color,
      Theme.of(tester.element(selectionSurface)).colorScheme.secondaryContainer,
    );
    expect(material.clipBehavior, Clip.antiAlias);
    expect(
      tester
          .widget<ListTile>(
            find.descendant(
              of: selectionSurface,
              matching: find.byType(ListTile),
            ),
          )
          .selectedTileColor,
      isNull,
    );

    final Finder channelList = find.byKey(
      const PageStorageKey<String>('channel-sidebar'),
    );
    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.descendant(of: channelList, matching: find.byType(Scrollable)),
    );
    final double scrollOffset =
        tester.getRect(selectionSurface).center.dy - searchRect.center.dy;
    scrollable.position.jumpTo(scrollOffset);
    await tester.pump();

    expect(
      tester.getRect(selectionSurface).center.dy,
      lessThan(tester.getRect(channelList).top),
    );
    expect(tester.widget<ListView>(channelList).clipBehavior, Clip.hardEdge);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses compact vertical spacing for channel rows', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    final Finder channelTile = find.ancestor(
      of: find.text('Town Square'),
      matching: find.byType(ListTile),
    );
    expect(
      tester.widget<ListTile>(channelTile).visualDensity,
      const VisualDensity(vertical: -2),
    );
  });

  testWidgets('applies collapsed and muted category presentation', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(
            _CollapsedMutedSidebarRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Muted category'), findsOneWidget);
    expect(find.text('Quiet channel'), findsNothing);
    expect(
      tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.text('Muted category'),
              matching: find.byType(Opacity),
            ),
          )
          .any((Opacity opacity) => opacity.opacity == 0.55),
      isTrue,
    );

    await tester.tap(find.text('Muted category'));
    await tester.pumpAndSettle();
    expect(find.text('Quiet channel'), findsOneWidget);
    expect(
      tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.text('Quiet channel'),
              matching: find.byType(Opacity),
            ),
          )
          .any((Opacity opacity) => opacity.opacity == 0.55),
      isTrue,
    );
  });

  testWidgets('shows the compact channel list at large text scale', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: BootstrapPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _SignedOutRepository implements AuthRepository {
  @override
  Future<AuthSession> authenticateWithPassword({
    required Uri serverUrl,
    required String loginId,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<AuthenticationMethods> discoverAuthenticationMethods({
    required Uri serverUrl,
  }) => throw UnimplementedError();

  @override
  Future<AuthSession> authenticateWithSessionToken({
    required Uri serverUrl,
    required String token,
  }) => throw UnimplementedError();

  @override
  Future<AuthSession> authenticateWithSso({
    required Uri serverUrl,
    required SsoProvider provider,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelSsoAuthentication() async {}

  @override
  Future<List<SsoOption>> discoverSsoOptions({required Uri serverUrl}) async =>
      const <SsoOption>[];

  @override
  Future<AuthSession?> restoreSession() async => null;

  @override
  Future<void> signOut() async {}
}

class _DelayedPostRepository extends PostRepository {
  const _DelayedPostRepository({
    this.delay = const Duration(milliseconds: 800),
  });

  final Duration delay;

  Future<List<ChannelPost>> _posts(String channelId) async {
    await Future<void>.delayed(delay);
    return <ChannelPost>[
      ChannelPost(
        id: '$channelId-post',
        channelId: channelId,
        author: const PostAuthor(id: 'grace', displayName: 'Grace Hopper'),
        sentAt: DateTime(2026, 8, 24, 10, 30),
        message: 'Message for $channelId',
        reactions: const <PostReaction>[PostReaction(emoji: '👍', count: 3)],
        replyCount: 2,
        lastReplyAt: DateTime(2026, 8, 24, 10, 35),
      ),
      ChannelPost(
        id: '$channelId-follow-up-1',
        channelId: channelId,
        author: const PostAuthor(id: 'grace', displayName: 'Grace Hopper'),
        sentAt: DateTime(2026, 8, 24, 10, 31),
        message: 'Follow-up message 1',
      ),
      ChannelPost(
        id: '$channelId-follow-up-2',
        channelId: channelId,
        author: const PostAuthor(id: 'grace', displayName: 'Grace Hopper'),
        sentAt: DateTime(2026, 8, 24, 10, 32),
        message: 'Follow-up message 2',
      ),
    ];
  }

  @override
  Future<ChannelPostPage> loadOlder({
    required AuthSession session,
    required String channelId,
    required String beforePostId,
  }) async => const ChannelPostPage();

  @override
  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  }) async => ChannelPostPage(posts: await _posts(channelId), hasOlder: false);
}

final class _PermalinkPostRepository extends PostRepository {
  _PermalinkPostRepository({
    this.replyTarget = false,
    this.replyPostId = 'reply-20',
  });

  final bool replyTarget;
  final String replyPostId;
  String? resolvedPostId;
  String? aroundPostId;

  static const SidebarChannel _channel = SidebarChannel(
    id: 'town-square',
    teamId: 'team-1',
    name: 'town-square',
    displayName: 'Town Square',
    kind: ChannelKind.publicChannel,
  );

  ChannelPost _post(String id, String message, int minute) => ChannelPost(
    id: id,
    channelId: _channel.id,
    author: const PostAuthor(id: 'grace', displayName: 'Grace Hopper'),
    sentAt: DateTime(2026, 8, 24, 10, minute),
    message: message,
    replyCount: id == 'town-square-post' ? 2 : 0,
  );

  @override
  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  }) async {
    if (channelId == 'direct-grace') {
      return ChannelPostPage(
        posts: <ChannelPost>[
          ChannelPost(
            id: 'direct-grace-post',
            channelId: channelId,
            author: const PostAuthor(id: 'grace', displayName: 'Grace Hopper'),
            sentAt: DateTime(2026, 8, 24, 10, 35),
            message: 'Message for direct-grace',
          ),
        ],
      );
    }
    return ChannelPostPage(
      posts: <ChannelPost>[
        _post(
          'source',
          replyTarget
              ? '[Open linked reply]('
                    'https://chat.example.com/team-a/pl/$replyPostId)'
              : '[Open linked root]('
                    'https://chat.example.com/team-a/pl/linked-root)',
          35,
        ),
      ],
    );
  }

  @override
  Future<PostNavigationTarget> resolveNavigationTarget({
    required AuthSession session,
    required String postId,
  }) async {
    resolvedPostId = postId;
    return PostNavigationTarget(
      linkedPostId: postId,
      channelPostId: replyTarget ? 'town-square-post' : 'linked-root',
      channel: _channel,
      threadRootPostId: replyTarget ? 'town-square-post' : null,
      threadHighlightedPostId: replyTarget ? postId : null,
    );
  }

  @override
  Future<ChannelPostPage> loadAround({
    required AuthSession session,
    required String channelId,
    required String postId,
  }) async {
    aroundPostId = postId;
    return ChannelPostPage(
      posts: <ChannelPost>[
        _post('oldest', 'Oldest message', 10),
        _post('older', 'Older message', 20),
        _post(postId, 'Historical linked message', 30),
        _post('newer', 'Newer message', 40),
      ],
      beforePostId: 'older',
      afterPostId: 'newer',
    );
  }

  @override
  Future<ChannelPostPage> loadOlder({
    required AuthSession session,
    required String channelId,
    required String beforePostId,
  }) async => const ChannelPostPage();
}

final class _ThreadRepository extends ThreadRepository {
  const _ThreadRepository({this.longThread = false});

  final bool longThread;

  MessageThread _thread(String rootPostId) => MessageThread(
    rootPostId: rootPostId,
    root: ChannelPost(
      id: rootPostId,
      channelId: 'town-square',
      author: const PostAuthor(id: 'grace', displayName: 'Grace Hopper'),
      sentAt: DateTime(2026, 8, 24, 10, 30),
      message: 'Message for town-square',
      replyCount: 2,
    ),
    replies: longThread
        ? List<ChannelPost>.generate(
            30,
            (int index) => ChannelPost(
              id: 'reply-$index',
              channelId: 'town-square',
              author: const PostAuthor(id: 'ada', displayName: 'Ada Lovelace'),
              sentAt: DateTime(2026, 8, 24, 10, 31 + index),
              message: 'Thread reply $index',
              rootId: rootPostId,
            ),
          )
        : <ChannelPost>[
            ChannelPost(
              id: 'reply-1',
              channelId: 'town-square',
              author: const PostAuthor(id: 'ada', displayName: 'Ada Lovelace'),
              sentAt: DateTime(2026, 8, 24, 10, 31),
              message: 'Thread reply 1',
              rootId: rootPostId,
            ),
            ChannelPost(
              id: 'reply-2',
              channelId: 'town-square',
              author: const PostAuthor(id: 'alan', displayName: 'Alan Turing'),
              sentAt: DateTime(2026, 8, 24, 10, 35),
              message: 'Deleted reply contents',
              rootId: rootPostId,
              isDeleted: true,
            ),
          ],
    isComplete: true,
    loadedAt: DateTime.fromMillisecondsSinceEpoch(123456),
  );

  @override
  Future<MessageThread> load({
    required AuthSession session,
    required String rootPostId,
  }) async => _thread(rootPostId);

  @override
  Future<void> markRead({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
    required DateTime timestamp,
  }) async {}
}

final class _RecordingPostRepository extends _DelayedPostRepository {
  _RecordingPostRepository() : super(delay: Duration.zero);

  String? channelId;
  String? rootPostId;
  String? message;
  String? pendingPostId;
  var _nextId = 0;

  @override
  Future<ChannelPost> sendText({
    required AuthSession session,
    required String channelId,
    required String message,
    required String pendingPostId,
    String rootPostId = '',
  }) async {
    this.channelId = channelId;
    this.rootPostId = rootPostId;
    this.message = message;
    this.pendingPostId = pendingPostId;
    _nextId += 1;
    return ChannelPost(
      id: 'sent-$_nextId',
      channelId: channelId,
      author: PostAuthor(id: session.userId, displayName: session.username),
      sentAt: DateTime(2026, 8, 25, 12, _nextId),
      message: message,
      rootId: rootPostId,
    );
  }
}

final class _AutoPagingPostRepository extends PostRepository {
  _AutoPagingPostRepository({
    this.startsEmpty = false,
    this.failLoads = false,
    this.neverCompletes = false,
  });

  final bool startsEmpty;
  final bool failLoads;
  final bool neverCompletes;
  int loadOlderCalls = 0;

  ChannelPost get _recent => ChannelPost(
    id: 'recent-root',
    channelId: 'town-square',
    author: const PostAuthor(id: 'ada', displayName: 'Ada'),
    sentAt: DateTime(2026, 8, 24, 12),
    message: 'Recent root',
    replyCount: 60,
  );

  ChannelPostPage get _initial => ChannelPostPage(
    posts: startsEmpty ? const <ChannelPost>[] : <ChannelPost>[_recent],
    replySummaries: startsEmpty
        ? <String, ChannelReplySummary>{
            'older-root': ChannelReplySummary(
              replyIds: const <String>{'reply-1'},
              lastReplyAt: DateTime(2026, 8, 24, 11, 30),
            ),
          }
        : const <String, ChannelReplySummary>{},
    beforePostId: 'cursor-0',
    hasOlder: true,
  );

  @override
  Future<ChannelPostPage> loadOlder({
    required AuthSession session,
    required String channelId,
    required String beforePostId,
  }) async {
    loadOlderCalls += 1;
    if (failLoads) throw StateError('paging failed');
    if (neverCompletes) {
      return ChannelPostPage(
        beforePostId: 'cursor-$loadOlderCalls',
        hasOlder: true,
      );
    }
    if (loadOlderCalls == 1) {
      return ChannelPostPage(
        replySummaries: startsEmpty
            ? const <String, ChannelReplySummary>{
                'older-root': ChannelReplySummary(
                  replyIds: <String>{'reply-1'},
                ),
              }
            : const <String, ChannelReplySummary>{},
        beforePostId: 'cursor-1',
        hasOlder: true,
      );
    }
    return ChannelPostPage(
      posts: <ChannelPost>[
        ChannelPost(
          id: 'older-root',
          channelId: channelId,
          author: const PostAuthor(id: 'grace', displayName: 'Grace'),
          sentAt: DateTime(2026, 8, 24, 11),
          message: 'Older root',
        ),
      ],
      hasOlder: false,
    );
  }

  @override
  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  }) async => _initial;
}

final class _SignedInRepository implements AuthRepository {
  @override
  Future<AuthSession> authenticateWithPassword({
    required Uri serverUrl,
    required String loginId,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<AuthenticationMethods> discoverAuthenticationMethods({
    required Uri serverUrl,
  }) => throw UnimplementedError();

  @override
  Future<AuthSession> authenticateWithSessionToken({
    required Uri serverUrl,
    required String token,
  }) => throw UnimplementedError();

  @override
  Future<AuthSession> authenticateWithSso({
    required Uri serverUrl,
    required SsoProvider provider,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelSsoAuthentication() async {}

  @override
  Future<List<SsoOption>> discoverSsoOptions({required Uri serverUrl}) async =>
      const <SsoOption>[];

  @override
  Future<AuthSession?> restoreSession() async => AuthSession(
    serverUrl: Uri.parse('https://chat.example.com'),
    userId: 'me',
    username: 'current',
  );

  @override
  Future<void> signOut() async {}
}

final class _CurrentProfileRepository implements CurrentUserProfileRepository {
  @override
  Future<CurrentUserProfile> load() async => const CurrentUserProfile(
    user: UserSummary(
      id: 'me',
      firstName: 'Ada',
      lastName: 'Lovelace',
      username: 'ada',
      nickname: '',
      position: '',
      email: 'ada@example.com',
    ),
    availability: Availability(presence: UserPresence.online),
  );

  @override
  Future<Availability> setAvailability({
    required UserPresence presence,
    required DateTime? expiresAt,
  }) async => Availability(presence: presence, expiresAt: expiresAt);

  @override
  Future<void> setCustomStatus({
    required String emoji,
    required String text,
    required CustomStatusDuration duration,
    required DateTime expiresAt,
  }) async {}

  @override
  Future<void> clearCustomStatus() async {}
}

final class _SidebarRepository implements ChannelRepository {
  @override
  Future<SidebarChannel> openDirectMessage({
    required String currentUserId,
    required String otherUserId,
    required String otherUserDisplayName,
  }) async => throw UnimplementedError();

  @override
  Future<ChannelSidebarSnapshot> load(AuthSession session) async =>
      const ChannelSidebarSnapshot(
        team: SidebarTeam(id: 'team-1', displayName: 'Example team'),
        sections: <SidebarSection>[
          SidebarSection(
            id: 'favorites',
            displayName: 'Favorites',
            channels: <SidebarChannel>[
              SidebarChannel(
                id: 'town-square',
                teamId: 'team-1',
                name: 'town-square',
                displayName: 'Town Square',
                kind: ChannelKind.publicChannel,
              ),
              SidebarChannel(
                id: 'direct-1',
                teamId: '',
                name: 'me__ada',
                displayName: 'Ada Lovelace',
                kind: ChannelKind.directMessage,
              ),
            ],
          ),
        ],
      );
}

final class _DirectMessageSidebarRepository implements ChannelRepository {
  static const SidebarChannel _townSquare = SidebarChannel(
    id: 'town-square',
    teamId: 'team-1',
    name: 'town-square',
    displayName: 'Town Square',
    kind: ChannelKind.publicChannel,
  );

  static const SidebarChannel _directGrace = SidebarChannel(
    id: 'direct-grace',
    teamId: '',
    name: 'me__grace',
    displayName: 'Grace Hopper',
    kind: ChannelKind.directMessage,
  );

  @override
  Future<SidebarChannel> openDirectMessage({
    required String currentUserId,
    required String otherUserId,
    required String otherUserDisplayName,
  }) async => _directGrace;

  @override
  Future<ChannelSidebarSnapshot> load(AuthSession session) async =>
      const ChannelSidebarSnapshot(
        team: SidebarTeam(id: 'team-1', displayName: 'Example team'),
        sections: <SidebarSection>[
          SidebarSection(
            id: 'favorites',
            displayName: 'Favorites',
            channels: <SidebarChannel>[_townSquare, _directGrace],
          ),
        ],
      );
}

final class _SearchSidebarRepository implements ChannelRepository {
  @override
  Future<SidebarChannel> openDirectMessage({
    required String currentUserId,
    required String otherUserId,
    required String otherUserDisplayName,
  }) async => throw UnimplementedError();

  @override
  Future<ChannelSidebarSnapshot> load(AuthSession session) async =>
      const ChannelSidebarSnapshot(
        team: SidebarTeam(id: 'team-1', displayName: 'Example team'),
        sections: <SidebarSection>[
          SidebarSection(
            id: 'public',
            displayName: 'Public channels',
            collapsed: true,
            channels: <SidebarChannel>[
              SidebarChannel(
                id: 'town-square',
                teamId: 'team-1',
                name: 'town-square',
                displayName: 'Town Square',
                kind: ChannelKind.publicChannel,
              ),
            ],
          ),
          SidebarSection(
            id: 'direct',
            displayName: 'Direct messages',
            channels: <SidebarChannel>[
              SidebarChannel(
                id: 'direct-ada',
                teamId: '',
                name: 'me__ada',
                displayName: 'Ada Lovelace',
                kind: ChannelKind.directMessage,
              ),
              SidebarChannel(
                id: 'direct-grace',
                teamId: '',
                name: 'me__grace',
                displayName: 'Grace Hopper',
                kind: ChannelKind.directMessage,
              ),
            ],
          ),
        ],
      );
}

final class _InboxTestRepository extends InboxRepository {
  @override
  Future<void> markRead({
    required AuthSession session,
    required InboxItem item,
  }) async {}

  @override
  Future<InboxSnapshot> load({required AuthSession session}) async {
    const SidebarChannel channel = SidebarChannel(
      id: 'town-square',
      teamId: 'team-1',
      name: 'town-square',
      displayName: 'Town Square',
      kind: ChannelKind.publicChannel,
    );
    final InboxPostCandidate candidate = InboxPostCandidate(
      post: Post(
        id: 'inbox-post',
        channelId: channel.id,
        author: const PostAuthor(id: 'ada', displayName: 'Ada Lovelace'),
        sentAt: DateTime(2026, 9, 3, 12),
        message: 'Inbox message',
      ),
      channel: channel,
      reason: InboxAttentionReason.directMention,
    );
    return InboxSnapshot(
      newItems: <InboxItem>[ChannelPostInboxItem(candidate: candidate)],
    );
  }
}

final class _RealtimeInboxTestRepository extends InboxRepository {
  final StreamController<InboxRealtimeEvent> _events =
      StreamController<InboxRealtimeEvent>();
  var loadCalls = 0;
  var reconnectCalls = 0;
  var watchCalls = 0;

  @override
  Future<InboxSnapshot> load({required AuthSession session}) async {
    loadCalls++;
    return InboxSnapshot();
  }

  @override
  Stream<InboxRealtimeEvent> watch({required AuthSession session}) {
    watchCalls++;
    return _events.stream;
  }

  @override
  void reconnectRealtime() => reconnectCalls++;

  void addPost(String id, String message) {
    const SidebarChannel channel = SidebarChannel(
      id: 'town-square',
      teamId: 'team-1',
      name: 'town-square',
      displayName: 'Town Square',
      kind: ChannelKind.publicChannel,
    );
    _events.add(
      InboxPostChanged(
        postId: id,
        candidate: InboxPostCandidate(
          post: Post(
            id: id,
            channelId: channel.id,
            author: const PostAuthor(id: 'ada', displayName: 'Ada Lovelace'),
            sentAt: DateTime(2026, 9, 7, 12),
            message: message,
          ),
          channel: channel,
          reason: InboxAttentionReason.directMention,
        ),
      ),
    );
  }

  @override
  Future<void> markRead({
    required AuthSession session,
    required InboxItem item,
  }) async {}

  Future<void> dispose() => _events.close();
}

final class _PostponedTestRepository extends PostponedRepository {
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

final class _LargeSidebarRepository implements ChannelRepository {
  @override
  Future<SidebarChannel> openDirectMessage({
    required String currentUserId,
    required String otherUserId,
    required String otherUserDisplayName,
  }) async => throw UnimplementedError();

  @override
  Future<ChannelSidebarSnapshot> load(AuthSession session) async =>
      ChannelSidebarSnapshot(
        team: const SidebarTeam(id: 'team-1', displayName: 'Example team'),
        sections: <SidebarSection>[
          SidebarSection(
            id: 'large',
            displayName: 'Large category',
            channels: List<SidebarChannel>.generate(
              200,
              (int index) => SidebarChannel(
                id: 'channel-$index',
                teamId: 'team-1',
                name: 'channel-$index',
                displayName: 'Channel $index',
                kind: ChannelKind.publicChannel,
              ),
              growable: false,
            ),
          ),
        ],
      );
}

final class _CollapsedMutedSidebarRepository implements ChannelRepository {
  @override
  Future<SidebarChannel> openDirectMessage({
    required String currentUserId,
    required String otherUserId,
    required String otherUserDisplayName,
  }) async => throw UnimplementedError();

  @override
  Future<ChannelSidebarSnapshot> load(AuthSession session) async =>
      const ChannelSidebarSnapshot(
        team: SidebarTeam(id: 'team-1', displayName: 'Example team'),
        sections: <SidebarSection>[
          SidebarSection(
            id: 'muted',
            displayName: 'Muted category',
            collapsed: true,
            muted: true,
            channels: <SidebarChannel>[
              SidebarChannel(
                id: 'quiet',
                teamId: 'team-1',
                name: 'quiet',
                displayName: 'Quiet channel',
                kind: ChannelKind.publicChannel,
              ),
            ],
          ),
        ],
      );
}
