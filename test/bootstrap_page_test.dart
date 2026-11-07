import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/auth_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/channel_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/sidebar_view_preferences_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/features/channel_members/domain/channel_member.dart';
import 'package:mattermost_flutter/src/features/channel_members/domain/channel_members_repository.dart';
import 'package:mattermost_flutter/src/features/channel_members/presentation/channel_members_pane.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_counters.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/features/profile/domain/models/current_user_profile.dart';
import 'package:mattermost_flutter/src/features/profile/domain/repositories/current_user_profile_repository.dart';
import 'package:mattermost_flutter/src/ui/auth/auth_strings.dart';
import 'package:mattermost_flutter/src/ui/channels/channel_sidebar_strings.dart';
import 'package:mattermost_flutter/src/ui/channels/selected_channel_controller.dart';
import 'package:mattermost_flutter/src/ui/channels/widgets/channel_avatar.dart';
import 'package:mattermost_flutter/src/ui/channels/widgets/channel_sidebar.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_spacing.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_content.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';
import 'package:mattermost_flutter/src/ui/shell/shell_page.dart';
import 'package:mattermost_flutter/src/ui/threads/widgets/thread_pane.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'support/fake_user_repository.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> selectInbox(WidgetTester tester) async {
    final Finder desktop = find.byKey(
      const ValueKey<String>('shell-inbox-destination'),
    );
    if (desktop.evaluate().isNotEmpty) {
      await tester.tap(desktop);
    } else {
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('shell-bottom-navigation')),
          matching: find.text('Inbox'),
        ),
      );
    }
    await tester.pumpAndSettle();
  }

  testWidgets('keeps sign-in hidden while the saved session is unresolved', (
    WidgetTester tester,
  ) async {
    final Completer<AuthSession?> restoration = Completer<AuthSession?>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _SignedOutRepository(restoration: restoration.future),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('app-startup')), findsOneWidget);
    expect(find.text(AuthStrings.title), findsNothing);
    expect(find.byType(ChannelSidebar), findsNothing);

    restoration.complete(null);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('app-startup')), findsNothing);
    expect(find.text(AuthStrings.title), findsOneWidget);
  });

  testWidgets('shows no navigation chrome while signed out', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final Size size in <Size>[
      const Size(390, 844),
      const Size(1120, 800),
    ]) {
      await tester.binding.setSurfaceSize(size);
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
      expect(scaffold.appBar, isNull);
      expect(scaffold.drawer, isNull);
      expect(find.byType(Drawer), findsNothing);
      expect(find.byType(ChannelSidebar), findsNothing);
      expect(find.text(AuthStrings.title), findsOneWidget);
    }
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
      find.byKey(const ValueKey<String>('shell-inbox-destination')),
      findsOneWidget,
    );
    expect(find.byType(NavigationRail), findsNothing);
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

  testWidgets('desktop uses the balanced header with icon destinations', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
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

    final Finder channels = find.byKey(
      const ValueKey<String>('shell-channels-destination'),
    );
    final Finder inbox = find.byKey(
      const ValueKey<String>('shell-inbox-destination'),
    );
    final Finder profile = find.byKey(
      const ValueKey<String>('shell-profile-destination'),
    );
    expect(find.byType(NavigationRail), findsNothing);
    expect(channels, findsOneWidget);
    expect(inbox, findsOneWidget);
    expect(profile, findsOneWidget);
    expect(tester.getCenter(channels).dx, lessThan(tester.getCenter(inbox).dx));
    expect(
      tester.getCenter(inbox).dx,
      lessThan(tester.getCenter(find.text('Example team')).dx),
    );
    final Rect sidePane = tester.getRect(
      find.byKey(const ValueKey<String>('channels-side-pane')),
    );
    final Rect footer = tester.getRect(
      find.byKey(const ValueKey<String>('sidebar-profile-footer')),
    );
    expect(tester.getCenter(profile).dx, lessThan(sidePane.right));
    expect(footer.bottom, sidePane.bottom);
    expect(
      tester
          .getRect(
            find
                .descendant(
                  of: find.byKey(const ValueKey<String>('channels-side-pane')),
                  matching: find.byType(Divider),
                )
                .last,
          )
          .bottom,
      footer.top,
    );
    expect(
      tester.getCenter(profile).dy,
      inInclusiveRange(footer.top, footer.bottom),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('channels-side-pane')),
        matching: find.text('Example team'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('shell-search-destination')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop header remains usable at large text scale', (
    WidgetTester tester,
  ) async {
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

    for (final double width in <double>[700, 1119, 1120]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('shell-channels-destination')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('shell-inbox-destination')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('shell-profile-destination')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('opens avatar menu from the desktop sidebar and logs out', (
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
    final Rect sidePane = tester.getRect(
      find.byKey(const ValueKey<String>('channels-side-pane')),
    );
    final Rect footer = tester.getRect(
      find.byKey(const ValueKey<String>('sidebar-profile-footer')),
    );
    expect(tester.getCenter(profileDestination).dx, lessThan(sidePane.right));
    expect(footer.bottom, sidePane.bottom);
    expect(
      tester.getCenter(profileDestination).dy,
      inInclusiveRange(footer.top, footer.bottom),
    );

    await tester.tap(profileDestination);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('profile-avatar-menu')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('profile-avatar-menu')),
        matching: find.text('Ada Lovelace'),
      ),
      findsOneWidget,
    );
    expect(find.text('@ada'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('profile-menu-away')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('profile-menu-custom-status')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('profile-menu-profile')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('profile-menu-profile')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('profile-logout')),
      findsOneWidget,
    );

    await tester.tap(profileDestination);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('profile-menu-logout')));
    await tester.pumpAndSettle();
    expect(find.text(AuthStrings.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens avatar menu from the rightmost compact destination', (
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

    expect(
      find.byKey(const ValueKey<String>('profile-avatar-menu')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('profile-menu-profile')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('profile-logout')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('changes availability and custom status from the avatar menu', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _CurrentProfileRepository profileRepository =
        _CurrentProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          currentUserProfileRepositoryProvider.overrideWithValue(
            profileRepository,
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    final Finder avatar = find.byKey(
      const ValueKey<String>('shell-profile-destination'),
    );
    await tester.tap(avatar);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('profile-menu-doNotDisturb')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('availability-expiry-thirtyMinutes')),
    );
    await tester.pumpAndSettle();
    expect(profileRepository.lastPresence, UserPresence.doNotDisturb);
    expect(profileRepository.lastAvailabilityExpiry, isNotNull);

    await tester.tap(avatar);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('profile-menu-custom-status')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('custom-status-save')),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('custom-status-text')),
      'Planning',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('custom-status-save')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey<String>('custom-status-save')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(profileRepository.lastCustomStatusText, 'Planning');

    await tester.tap(avatar);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('profile-menu-offline')),
    );
    await tester.pumpAndSettle();
    expect(profileRepository.lastPresence, UserPresence.offline);
    await tester.tap(avatar);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('profile-menu-offline')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(600, 500));
    await tester.pumpAndSettle();

    profileRepository.failAvailability = true;
    await tester.tap(avatar);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('profile-menu-away')));
    await tester.pumpAndSettle();
    expect(find.text('Could not update your status.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keeps the avatar menu usable with large text on compact layout',
    (WidgetTester tester) async {
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
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const BootstrapPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('shell-bottom-navigation')),
          matching: find.text('Profile'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('profile-avatar-menu')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('profile-menu-profile')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('profile-menu-profile')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('profile-scroll-view')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

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
    expect(
      find.byKey(const ValueKey<String>('shell-inbox-destination')),
      findsOneWidget,
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
    expect(find.text('FAVORITES'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('channel-section-marker-favorites')),
      findsOneWidget,
    );
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
    'opens Threads as the sole selection with channel-matched sidebar sizing',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final List<String> markedThreads = <String>[];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_SignedInRepository()),
            channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
            postRepositoryProvider.overrideWithValue(
              const _DelayedPostRepository(delay: Duration.zero),
            ),
            threadRepositoryProvider.overrideWithValue(
              _ThreadRepository(onMarkRead: markedThreads.add),
            ),
          ],
          child: const MaterialApp(home: BootstrapPage()),
        ),
      );
      await tester.pumpAndSettle();

      final Finder search = find.byKey(
        const ValueKey<String>('channel-search-field'),
      );
      final Finder threadsTile = find.byKey(
        const ValueKey<String>('threads-sidebar-tile'),
      );
      final Finder channelSelectionSurface = find.byKey(
        const ValueKey<String>('channel-selection-surface-town-square'),
      );
      expect(
        tester.getSize(threadsTile).width,
        tester.getSize(channelSelectionSurface).width,
      );
      expect(
        tester.getSize(search).width +
            tester
                .getSize(
                  find.byKey(const ValueKey<String>('read-channel-filter')),
                )
                .width +
            tester
                .getSize(
                  find.byKey(
                    const ValueKey<String>('folder-visibility-toggle'),
                  ),
                )
                .width +
            AppSpacing.xs,
        tester.getSize(threadsTile).width,
      );
      final double sidebarWidth = tester
          .getSize(find.byKey(const PageStorageKey<String>('channel-sidebar')))
          .width;
      expect(
        tester.getSize(channelSelectionSurface).width,
        sidebarWidth - 2 * AppLayout.sidebarItemInset,
      );
      expect(
        tester.widget<Text>(find.text(ChannelSidebarStrings.threads)).style,
        Theme.of(tester.element(threadsTile)).textTheme.bodyMedium!.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      );
      expect(
        (tester.widget<Material>(threadsTile).shape! as RoundedRectangleBorder)
            .borderRadius,
        BorderRadius.circular(AppSpacing.sm),
      );
      final Finder searchIcon = find.descendant(
        of: search,
        matching: find.byIcon(Icons.search),
      );
      final Finder threadsIcon = find.descendant(
        of: threadsTile,
        matching: find.byIcon(Icons.forum_outlined),
      );
      final Finder channelIcon = find.descendant(
        of: channelSelectionSurface,
        matching: find.byIcon(Icons.tag),
      );
      expect(
        tester.getTopLeft(searchIcon).dx,
        tester.getTopLeft(threadsIcon).dx,
      );
      expect(
        tester.getTopLeft(threadsIcon).dx,
        tester.getTopLeft(channelIcon).dx,
      );
      expect(
        tester.getTopLeft(find.text(ChannelSidebarStrings.searchHint)).dx -
            (tester.getTopLeft(searchIcon).dx +
                tester.getSize(searchIcon).width),
        AppSpacing.lg,
      );

      await tester.tap(find.text('Town Square'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Material>(channelSelectionSurface).color,
        Theme.of(
          tester.element(channelSelectionSurface),
        ).colorScheme.secondaryContainer,
      );

      await tester.tap(threadsTile);
      await tester.pumpAndSettle();

      expect(
        tester.widget<Material>(channelSelectionSurface).color,
        Colors.transparent,
      );
      expect(
        tester.widget<Material>(threadsTile).color,
        Theme.of(tester.element(threadsTile)).colorScheme.secondaryContainer,
      );
      final Rect threadsRect = tester.getRect(threadsTile);
      final Rect sidebarRect = tester.getRect(
        find.byKey(const ValueKey<String>('channels-side-pane')),
      );
      expect(threadsRect.left, sidebarRect.left + AppLayout.sidebarItemInset);
      expect(threadsRect.right, sidebarRect.right - AppLayout.sidebarItemInset);
      expect(
        find.byKey(const ValueKey<String>('channels-side-pane')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('followed-threads-list-pane')),
        findsOneWidget,
      );
      expect(find.text('Unread followed thread'), findsOneWidget);
      expect(find.text('Read followed thread'), findsOneWidget);
      expect(find.text('All your threads'), findsNothing);
      expect(find.text('Unreads'), findsNothing);
      expect(find.text('Done'), findsNothing);
      expect(find.text('Postpone'), findsNothing);
      expect(
        tester.widget<ThreadPane>(find.byType(ThreadPane)).rootPostId,
        'unread-root',
      );
      expect(
        tester.widget<ThreadPane>(find.byType(ThreadPane)).markReadOnOpen,
        isFalse,
      );
      expect(
        find.byKey(const ValueKey<String>('thread-unread-count-unread-root')),
        findsOneWidget,
      );
      expect(markedThreads, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey<String>('followed-thread-card-unread-root')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ThreadPane), findsOneWidget);
      expect(
        tester.widget<ThreadPane>(find.byType(ThreadPane)).markReadOnOpen,
        isTrue,
      );
      expect(markedThreads, <String>['unread-root']);
      expect(
        find.byKey(const ValueKey<String>('thread-unread-count-unread-root')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('channels-side-pane')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('followed-threads-list-pane')),
        findsOneWidget,
      );
      final Finder listPane = find.byKey(
        const ValueKey<String>('followed-threads-list-pane'),
      );
      final double listWidth = tester.getSize(listPane).width;
      final double threadWidth = tester.getSize(find.byType(ThreadPane)).width;
      expect(threadWidth, closeTo((listWidth + threadWidth) * 0.6, 1));
      expect(listWidth, greaterThanOrEqualTo(320));
      expect(tester.takeException(), isNull);

      final Finder divider = find.byKey(
        const ValueKey<String>('followed-thread-pane-divider'),
      );
      await tester.drag(divider, const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(ThreadPane)).width,
        lessThan(threadWidth),
      );

      await tester.drag(divider, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(ThreadPane)).width,
        closeTo(threadWidth, 1),
      );

      await tester.tap(divider);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        tester.getSize(find.byType(ThreadPane)).width,
        closeTo(threadWidth - 20, 1),
      );
    },
  );

  testWidgets('falls back to the first thread when the selection disappears', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final List<String> markedThreads = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(
            const _DelayedPostRepository(delay: Duration.zero),
          ),
          threadRepositoryProvider.overrideWithValue(
            _ThreadRepository(onMarkRead: markedThreads.add),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('threads-sidebar-tile')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('followed-thread-card-read-root')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ThreadPane>(find.byType(ThreadPane)).rootPostId,
      'read-root',
    );

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(ThreadPane)),
    );
    container
        .read(followedThreadsProvider('team-1').notifier)
        .removeUnfollowedThread('read-root');
    await tester.pumpAndSettle();
    expect(
      tester.widget<ThreadPane>(find.byType(ThreadPane)).rootPostId,
      'unread-root',
    );
    expect(
      tester.widget<ThreadPane>(find.byType(ThreadPane)).markReadOnOpen,
      isFalse,
    );
    expect(markedThreads, isEmpty);

    await tester.tap(
      find.descendant(
        of: find.byType(ThreadPane),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ThreadPane), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('followed-thread-card-unread-root')),
    );
    await tester.pumpAndSettle();
    expect(markedThreads, <String>['unread-root']);
  });

  testWidgets('stacks followed threads from the compact channel list', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          threadRepositoryProvider.overrideWithValue(const _ThreadRepository()),
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

    await tester.tap(
      find.byKey(const ValueKey<String>('threads-sidebar-tile')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('followed-threads-list-pane')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('shell-bottom-navigation')),
      findsNothing,
    );
    expect(find.byType(BackButton), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const PageStorageKey<String>('channel-sidebar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('shell-bottom-navigation')),
      findsOneWidget,
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
      expect(tester.getSize(search).height, inInclusiveRange(40, 44));
      final TextField searchField = tester.widget<TextField>(search);
      final InputDecoration decoration = searchField.decoration!;
      expect(searchField.style?.fontSize, 13);
      expect(searchField.textAlignVertical, isNull);
      expect(decoration.hintStyle, isNull);
      expect(decoration.isDense, isTrue);
      expect(decoration.constraints, AppLayout.sidebarSearchConstraints);
      expect(
        decoration.contentPadding,
        const EdgeInsets.symmetric(vertical: AppSpacing.md),
      );
      expect(decoration.filled, isTrue);
      expect(
        decoration.prefixIconConstraints,
        AppLayout.sidebarSearchPrefixIconConstraints,
      );
      expect(decoration.enabledBorder, isA<OutlineInputBorder>());
      expect(decoration.focusedBorder, isA<OutlineInputBorder>());
      expect(
        (decoration.enabledBorder! as OutlineInputBorder).borderRadius,
        BorderRadius.circular(AppSpacing.sm),
      );
      expect(
        (decoration.enabledBorder! as OutlineInputBorder).borderSide.style,
        BorderStyle.solid,
      );
      expect(find.text('PUBLIC CHANNELS'), findsOneWidget);
      expect(find.text('Town Square'), findsNothing);
      expect(find.text('DIRECT MESSAGES'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      final Finder publicChannelsHeader = find.ancestor(
        of: find.text('PUBLIC CHANNELS'),
        matching: find.byType(ListTile),
      );
      final Finder publicChannelsExpander = find.descendant(
        of: publicChannelsHeader,
        matching: find.byIcon(Icons.expand_more),
      );
      expect(find.byTooltip('Refresh channels'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('threads-sidebar-tile')),
        findsOneWidget,
      );

      await tester.tap(search);
      await tester.pump();
      expect(tester.widget<TextField>(search).focusNode?.hasFocus, isTrue);

      await tester.enterText(search, 'town');
      await tester.pump();
      expect(tester.getSize(search).height, greaterThanOrEqualTo(40));
      expect(
        tester.getCenter(find.byTooltip(ChannelSidebarStrings.clearSearch)).dx,
        greaterThan(tester.getCenter(publicChannelsExpander).dx),
      );
      expect(find.text('PUBLIC CHANNELS'), findsOneWidget);
      expect(find.text('Town Square'), findsOneWidget);
      expect(find.text('DIRECT MESSAGES'), findsNothing);
      expect(find.text('Ada Lovelace'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('threads-sidebar-tile')),
        findsNothing,
      );

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(tester.widget<TextField>(search).focusNode?.hasFocus, isFalse);
      expect(find.text('Town Square'), findsOneWidget);

      await tester.tap(find.byTooltip(ChannelSidebarStrings.clearSearch));
      await tester.pump();
      expect(find.text('PUBLIC CHANNELS'), findsOneWidget);
      expect(find.text('Town Square'), findsNothing);
      expect(find.text('DIRECT MESSAGES'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.byTooltip(ChannelSidebarStrings.clearSearch), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('threads-sidebar-tile')),
        findsOneWidget,
      );

      await tester.enterText(search, 'ada');
      await tester.pump();
      expect(find.text('PUBLIC CHANNELS'), findsNothing);
      expect(find.text('DIRECT MESSAGES'), findsOneWidget);
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
    expect(find.text('@dev-team'), findsOneWidget);
    expect(find.text('mentioned'), findsOneWidget);
    expect(find.text('Inbox message'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('postpone-post:inbox-post')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('postpone-post:inbox-post')),
    );
    await tester.pumpAndSettle();
    expect(find.text('No new messages'), findsOneWidget);

    await tester.tap(find.text('Postponed'));
    await tester.pumpAndSettle();
    expect(find.text('Inbox message'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('remove-post:inbox-post')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('remove-post:inbox-post')),
    );
    await tester.pumpAndSettle();
    expect(find.text('No postponed messages'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shows the stored Inbox indicator while the startup load is pending',
    (WidgetTester tester) async {
      final _DeferredInboxTestRepository inbox = _DeferredInboxTestRepository();
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
      for (var index = 0; index < 10 && inbox.loadCalls == 0; index++) {
        await tester.pump(const Duration(milliseconds: 1));
      }

      expect(inbox.loadCalls, 1);
      expect(
        find.byKey(const ValueKey<String>('inbox-navigation-indicator')),
        findsOneWidget,
      );

      inbox.snapshot.complete(InboxSnapshot());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('inbox-navigation-indicator')),
        findsNothing,
      );
    },
  );

  testWidgets('reopening Inbox reuses the app-owned snapshot', (
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
    expect(inbox.loadCalls, 1);

    await selectInbox(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('shell-channels-destination')),
    );
    await tester.pumpAndSettle();
    await selectInbox(tester);

    expect(inbox.loadCalls, 1);
    expect(inbox.watchCalls, 1);
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

  testWidgets('dismisses an Inbox notification after five seconds', (
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

    inbox.addPost('timed', 'A timed Inbox message');
    await tester.pumpAndSettle();

    final Finder notification = find.byKey(
      const ValueKey<String>('inbox-in-app-notification'),
    );
    expect(notification, findsOneWidget);
    expect(
      tester.widget<SnackBar>(notification).duration,
      const Duration(seconds: 5),
    );

    await tester.pump(const Duration(milliseconds: 4999));
    expect(notification, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(notification, findsNothing);
  });

  testWidgets('does not show Inbox notifications while Inbox is open', (
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
    await selectInbox(tester);

    inbox.addPost('already-open', 'An Inbox message received while open');
    await tester.pumpAndSettle();

    expect(find.text('An Inbox message received while open'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('inbox-in-app-notification')),
      findsNothing,
    );
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

  testWidgets('keeps channel message lines readable on a wide screen', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 800));
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
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();

    final Rect channelHeader = tester.getRect(
      find.byKey(const ValueKey<String>('channel-header')),
    );
    final double profileY = tester
        .getCenter(
          find.byKey(const ValueKey<String>('shell-profile-destination')),
        )
        .dy;
    expect(channelHeader.top, 0);
    expect(profileY, greaterThan(channelHeader.bottom));

    final Finder messageRow = find
        .ancestor(
          of: find.byType(MessageContent).first,
          matching: find.byType(Row),
        )
        .first;
    expect(
      tester.getSize(messageRow).width,
      lessThanOrEqualTo(AppLayout.readableContentWidth),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens channel members beside messages when width allows', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => appRouter.go('/'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(
            const _DelayedPostRepository(delay: Duration.zero),
          ),
          channelMembersRepositoryProvider.overrideWithValue(
            const _ChannelMembersRepository(),
          ),
          userRepositoryProvider.overrideWithValue(FakeUserRepository()),
        ],
        child: const MattermostApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('channel-member-count-town-square')),
    );
    await tester.pumpAndSettle();

    final Finder pane = find.byType(ChannelMembersPane);
    expect(pane, findsOneWidget);
    expect(tester.getSize(pane).width, 380);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('channels-side-pane')),
        matching: find.byKey(
          const ValueKey<String>('shell-profile-destination'),
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Message for town-square'), findsOneWidget);
    expect(
      find.descendant(of: pane, matching: find.text('Ada Lovelace')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens channel members as a full-size pane on compact width', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => appRouter.go('/'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(
            const _DelayedPostRepository(delay: Duration.zero),
          ),
          channelMembersRepositoryProvider.overrideWithValue(
            const _ChannelMembersRepository(),
          ),
          userRepositoryProvider.overrideWithValue(FakeUserRepository()),
        ],
        child: const MattermostApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('channel-member-count-town-square')),
    );
    await tester.pumpAndSettle();

    final Finder pane = find.byType(ChannelMembersPane);
    expect(pane, findsOneWidget);
    expect(tester.getSize(pane).width, 390);
    expect(
      find.descendant(of: pane, matching: find.text('Ada Lovelace')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ChannelMembersPane), findsNothing);
    expect(find.text('Message for town-square'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    final Rect channelHeader = tester.getRect(
      find.byKey(const ValueKey<String>('channel-header')),
    );
    final double profileY = tester
        .getCenter(
          find.byKey(const ValueKey<String>('shell-profile-destination')),
        )
        .dy;
    expect(profileY, greaterThan(channelHeader.bottom));
    expect(
      tester
          .getCenter(
            find.byKey(const ValueKey<String>('shell-profile-destination')),
          )
          .dx,
      lessThan(tester.getCenter(find.byType(ThreadPane)).dx),
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey<String>('channel-header-divider')),
          )
          .dy,
      tester
          .getTopLeft(
            find.byKey(const ValueKey<String>('thread-header-divider')),
          )
          .dy,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('thread-town-square-post')),
          )
          .width,
      380,
    );

    final Finder channelsPane = find.byKey(
      const ValueKey<String>('channels-side-pane'),
    );
    await tester.drag(
      find.byKey(const ValueKey<String>('channels-pane-divider')),
      const Offset(-40, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(channelsPane).width, 240);

    final Finder threadDivider = find.byKey(
      const ValueKey<String>('thread-pane-divider'),
    );
    await tester.drag(threadDivider, const Offset(-50, 0));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('thread-town-square-post')),
          )
          .width,
      430,
    );

    await tester.tap(threadDivider);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('thread-town-square-post')),
          )
          .width,
      410,
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

    await tester.tap(find.text('LARGE CATEGORY'));
    await tester.pumpAndSettle();
    expect(find.text('Channel 0'), findsNothing);

    await tester.tap(find.text('LARGE CATEGORY'));
    await tester.pumpAndSettle();
    expect(find.text('Channel 0'), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, lessThan(30));

    final Finder profile = find.byKey(
      const ValueKey<String>('shell-profile-destination'),
    );
    final Rect footer = tester.getRect(
      find.byKey(const ValueKey<String>('sidebar-profile-footer')),
    );
    await tester.drag(find.text('Channel 0'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Channel 0'), findsNothing);
    expect(
      tester.getRect(
        find.byKey(const ValueKey<String>('sidebar-profile-footer')),
      ),
      footer,
    );
    expect(
      tester.getCenter(profile).dy,
      inInclusiveRange(footer.top, footer.bottom),
    );
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
      (material.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(AppSpacing.sm),
    );
    final Finder channelList = find.byKey(
      const PageStorageKey<String>('channel-sidebar'),
    );
    final Rect selectionRect = tester.getRect(selectionSurface);
    final Rect listRect = tester.getRect(channelList);
    expect(selectionRect.left, listRect.left + AppLayout.sidebarItemInset);
    expect(selectionRect.right, listRect.right - AppLayout.sidebarItemInset);
    final ListTile selectedTile = tester.widget<ListTile>(
      find.descendant(of: selectionSurface, matching: find.byType(ListTile)),
    );
    expect(selectedTile.selectedTileColor, isNull);
    expect(
      (selectedTile.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(AppSpacing.sm),
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

  testWidgets('uses a compact 40 pixel channel row target', (
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
    expect(tester.getSize(channelTile).height, 40);
    expect(tester.getSize(channelTile).width, greaterThanOrEqualTo(40));
    final ListTile channelRow = tester.widget<ListTile>(channelTile);
    expect(channelRow.horizontalTitleGap, AppSpacing.xs);
    expect(channelRow.minLeadingWidth, 20);
    expect(tester.widget<Text>(find.text('Town Square')).style?.fontSize, 13);
    expect(
      tester
          .widget<ChannelAvatar>(
            find.descendant(
              of: channelTile,
              matching: find.byType(ChannelAvatar),
            ),
          )
          .size,
      18,
    );
    final Finder directMessageTile = find.ancestor(
      of: find.text('Ada Lovelace'),
      matching: find.byType(ListTile),
    );
    final Finder directMessageAvatar = find.descendant(
      of: directMessageTile,
      matching: find.byType(ChannelAvatar),
    );
    expect(tester.widget<ChannelAvatar>(directMessageAvatar).size, 16);
    expect(
      tester.getRect(find.text('Ada Lovelace')).left,
      tester.getRect(find.text('Town Square')).left,
    );
    expect(
      tester.getRect(find.text('Ada Lovelace')).left -
          tester.getRect(directMessageAvatar).right,
      greaterThanOrEqualTo(6),
    );
    final Finder channelSurface = find.byKey(
      const ValueKey<String>('channel-selection-surface-town-square'),
    );
    final InkWell hoverTarget = tester.widget<InkWell>(
      find.descendant(of: channelSurface, matching: find.byType(InkWell)).first,
    );
    expect(
      (hoverTarget.customBorder! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(AppSpacing.sm),
    );
    final Finder groupSurface = find.byKey(
      const ValueKey<String>('channel-section-surface-favorites'),
    );
    final Finder sidebarList = find.byKey(
      const PageStorageKey<String>('channel-sidebar'),
    );
    expect(
      tester.getRect(groupSurface).left,
      tester.getRect(sidebarList).left + AppLayout.sidebarItemInset,
    );
    expect(
      tester.getRect(groupSurface).right,
      tester.getRect(sidebarList).right - AppLayout.sidebarItemInset,
    );
    final ListTile groupRow = tester.widget<ListTile>(
      find.descendant(of: groupSurface, matching: find.byType(ListTile)),
    );
    expect(groupRow.leading, isNotNull);
    expect(groupRow.trailing, isNull);
    expect(groupRow.horizontalTitleGap, AppSpacing.xs);
    expect(find.text('FAVORITES'), findsOneWidget);
    expect(tester.getSize(groupSurface).height, greaterThanOrEqualTo(40));
    expect(
      (tester.widget<Material>(groupSurface).shape! as RoundedRectangleBorder)
          .borderRadius,
      BorderRadius.circular(AppSpacing.sm),
    );
    final InkWell groupHoverTarget = tester.widget<InkWell>(
      find.descendant(of: groupSurface, matching: find.byType(InkWell)).first,
    );
    expect(
      (groupHoverTarget.customBorder! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(AppSpacing.sm),
    );
  });

  testWidgets('highlights unread channels at compact and expanded widths', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final Size size in <Size>[
      const Size(390, 844),
      const Size(1000, 800),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_SignedInRepository()),
            channelRepositoryProvider.overrideWithValue(
              _UnreadSidebarRepository(),
            ),
          ],
          child: MaterialApp(
            theme: size.width < 700
                ? ThemeData.light(useMaterial3: true)
                : ThemeData.dark(useMaterial3: true),
            home: const BootstrapPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Text unread = tester.widget<Text>(find.text('Unread channel'));
      final Text read = tester.widget<Text>(find.text('Read channel'));
      final Text mutedUnread = tester.widget<Text>(
        find.text('Muted unread channel'),
      );

      expect(unread.style?.fontWeight, FontWeight.w400);
      expect(unread.semanticsLabel, 'Unread channel, unread');
      expect(read.style?.fontWeight, FontWeight.w400);
      expect(mutedUnread.style?.fontWeight, FontWeight.w400);
      final Finder dot = find.byKey(
        const ValueKey<String>('channel-unread-dot-unread'),
      );
      expect(dot, findsOneWidget);
      final Finder surface = find.byKey(
        const ValueKey<String>('channel-selection-surface-unread'),
      );
      expect(
        tester.getRect(dot).left -
            tester.getRect(find.text('Unread channel')).right,
        greaterThan(AppSpacing.xxl),
      );
      expect(
        tester.getRect(surface).right - tester.getRect(dot).right,
        lessThanOrEqualTo(AppSpacing.xxl),
      );
      expect(
        find.byKey(const ValueKey<String>('channel-unread-dot-read')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('channel-unread-dot-muted-unread')),
        findsNothing,
      );
    }
  });

  testWidgets('shows a direct participant custom status beside the name', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final Size size in <Size>[
      const Size(390, 844),
      const Size(1000, 800),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_SignedInRepository()),
            channelRepositoryProvider.overrideWithValue(
              _CustomStatusSidebarRepository(),
            ),
          ],
          child: MaterialApp(
            home: const BootstrapPage(),
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder direct = find.byKey(
        const ValueKey<String>('channel-selection-surface-direct-ada'),
      );
      expect(
        find.descendant(of: direct, matching: find.text('📆')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: direct, matching: find.byTooltip('In a meeting')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('channel-custom-status-bot')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('search expands into the filter button space while focused', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final Size size in <Size>[
      const Size(390, 844),
      const Size(1000, 800),
      const Size(1280, 800),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_SignedInRepository()),
            channelRepositoryProvider.overrideWithValue(
              _UnreadSidebarRepository(),
            ),
          ],
          child: const MaterialApp(home: BootstrapPage()),
        ),
      );
      await tester.pumpAndSettle();

      final Finder search = find.byKey(
        const ValueKey<String>('channel-search-field'),
      );
      final double idleWidth = tester.getSize(search).width;
      final Finder threads = find.byKey(
        const ValueKey<String>('threads-sidebar-tile'),
      );
      final double threadsTop = tester.getRect(threads).top;
      final Finder hideRead = find.byTooltip('Hide read channels');
      final Finder folderToggle = find.byKey(
        const ValueKey<String>('folder-visibility-toggle'),
      );
      expect(hideRead, findsOneWidget);
      expect(folderToggle, findsOneWidget);
      expect(tester.getSize(hideRead).width, greaterThanOrEqualTo(40));

      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(tester.getSize(search).width, greaterThan(idleWidth + 80));
      expect(hideRead, findsNothing);
      expect(folderToggle, findsNothing);
      expect(tester.getRect(threads).top, threadsTop);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(tester.getSize(search).width, idleWidth);
      expect(hideRead, findsOneWidget);
      expect(folderToggle, findsOneWidget);
    }
  });

  testWidgets('read filter hides read channels and empty categories', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(
            _ReadFilterSidebarRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EMPTY'), findsNothing);
    expect(find.text('MIXED'), findsOneWidget);
    expect(find.text('READ ONLY'), findsOneWidget);
    expect(find.text('Read channel'), findsOneWidget);
    expect(find.text('Unread channel'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide read channels'));
    await tester.pumpAndSettle();
    expect(find.text('MIXED'), findsOneWidget);
    expect(find.text('READ ONLY'), findsNothing);
    expect(find.text('Read channel'), findsNothing);
    expect(find.text('Unread channel'), findsOneWidget);
    expect(find.byTooltip('Show read channels'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide folder headings'));
    await tester.pumpAndSettle();
    expect(find.text('MIXED'), findsNothing);
    expect(find.text('Unread channel'), findsOneWidget);
    expect(find.text('Read channel'), findsNothing);

    await tester.tap(find.byTooltip('Show folder headings'));
    await tester.pumpAndSettle();
    expect(find.text('MIXED'), findsOneWidget);
    expect(find.text('Read channel'), findsNothing);

    await tester.tap(find.byTooltip('Show read channels'));
    await tester.pumpAndSettle();
    expect(find.text('READ ONLY'), findsOneWidget);
    expect(find.text('Read channel'), findsOneWidget);
    expect(find.text('EMPTY'), findsNothing);
  });

  testWidgets('favorites stay visible above read filtering and show a star', (
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
    await tester.tap(find.byTooltip(ChannelSidebarStrings.hideReadChannels));
    await tester.pumpAndSettle();

    expect(find.text('Town Square'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('channel-favorite-star-town-square')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip(ChannelSidebarStrings.hideFolderHeadings));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('channel-favorite-star-town-square')),
      findsOneWidget,
    );
  });

  testWidgets('read filter hides muted activity but keeps mentions', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(
            _UnreadSidebarRepository(),
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
    await tester.tap(find.byTooltip(ChannelSidebarStrings.hideReadChannels));
    await tester.pumpAndSettle();

    expect(find.text('Muted unread channel'), findsNothing);
    expect(find.text('Muted mentioned channel'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('channel-unread-dot-muted-mentioned')),
      findsOneWidget,
    );
  });

  testWidgets('read filter marks mentions in a collapsed muted folder', (
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
    await tester.tap(find.byTooltip(ChannelSidebarStrings.hideReadChannels));
    await tester.pumpAndSettle();

    expect(find.text('MUTED CATEGORY'), findsOneWidget);
    expect(find.text('Unread in category'), findsNothing);
    expect(find.text('Mention in category'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('channel-section-unread-dot-muted')),
      findsOneWidget,
    );
  });

  testWidgets('secondary click opens actions for a channel', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(
            _ReadFilterSidebarRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('Unread channel')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Mark as unread'), findsOneWidget);
    expect(find.text('Add to favorites'), findsOneWidget);
    expect(find.text('Mute channel'), findsOneWidget);
    expect(find.text('Move to…'), findsOneWidget);
    expect(find.text('Close conversation'), findsNothing);
  });

  testWidgets('favorite dialog menu offers removal and close', (
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

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('Ada Lovelace')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text(ChannelSidebarStrings.removeFavorite), findsOneWidget);
    expect(find.text(ChannelSidebarStrings.closeConversation), findsOneWidget);
  });

  testWidgets('channel menu confirms leaving before removing membership', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _ReadFilterSidebarRepository repository =
        _ReadFilterSidebarRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(repository),
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

    Future<void> openMenu() async {
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text('Unread channel')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await openMenu();
    expect(find.text('Покинуть канал'), findsOneWidget);
    await tester.tap(find.text('Покинуть канал'));
    await tester.pumpAndSettle();
    expect(find.text('Покинуть канал?'), findsOneWidget);
    expect(repository.lastAction, isNull);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(repository.lastAction, isNull);

    await openMenu();
    await tester.tap(find.text('Покинуть канал'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Покинуть'));
    await tester.pumpAndSettle();
    expect(repository.lastAction, 'leave:unread');
  });

  testWidgets('keyboard context shortcut opens channel actions', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(
            _ReadFilterSidebarRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    Focus.of(
      tester.element(
        find.byKey(const ValueKey<String>('channel-selection-surface-unread')),
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text(ChannelSidebarStrings.markUnread), findsOneWidget);
  });

  testWidgets('channel menu runs actions and lists empty folders', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _ReadFilterSidebarRepository repository =
        _ReadFilterSidebarRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> openMenu() async {
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text('Unread channel')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await openMenu();
    await tester.tap(find.text(ChannelSidebarStrings.markUnread));
    await tester.pumpAndSettle();
    expect(repository.lastAction, 'unread:unread');

    await openMenu();
    await tester.tap(find.text(ChannelSidebarStrings.moveTo));
    await tester.pumpAndSettle();
    expect(find.text('Empty folder'), findsOneWidget);
    await tester.tap(find.text('Empty folder'));
    await tester.pumpAndSettle();
    expect(repository.lastAction, 'move:unread:empty');
  });

  testWidgets('restores both sidebar toggles after reopening the app', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Widget app() => ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_SignedInRepository()),
        channelRepositoryProvider.overrideWithValue(
          _ReadFilterSidebarRepository(),
        ),
      ],
      child: const MaterialApp(home: BootstrapPage()),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hide read channels'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hide folder headings'));
    await tester.pumpAndSettle();
    expect(find.text('Read channel'), findsNothing);
    expect(find.text('MIXED'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show read channels'), findsOneWidget);
    expect(find.byTooltip('Show folder headings'), findsOneWidget);
    expect(find.text('Read channel'), findsNothing);
    expect(find.text('MIXED'), findsNothing);
    expect(find.text('Unread channel'), findsOneWidget);
  });

  testWidgets('restores the previous filter when saving fails', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(
            _ReadFilterSidebarRepository(),
          ),
          sidebarViewPreferencesRepositoryProvider.overrideWithValue(
            _FailingSidebarPreferencesRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Hide read channels'));
    await tester.pumpAndSettle();
    expect(find.text('Read channel'), findsOneWidget);
    expect(find.byTooltip('Hide read channels'), findsOneWidget);
    expect(
      find.text(ChannelSidebarStrings.preferencesSaveFailed),
      findsOneWidget,
    );
  });

  testWidgets('read filter explains an empty unread list', (
    WidgetTester tester,
  ) async {
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

    await tester.tap(find.byTooltip('Hide read channels'));
    await tester.pumpAndSettle();
    expect(find.text('PUBLIC CHANNELS'), findsNothing);
    expect(find.text('DIRECT MESSAGES'), findsNothing);
    expect(find.text('No unread channels'), findsOneWidget);

    await tester.tap(find.byTooltip('Show read channels'));
    await tester.pumpAndSettle();
    expect(find.text('PUBLIC CHANNELS'), findsOneWidget);
    expect(find.text('DIRECT MESSAGES'), findsOneWidget);
  });

  testWidgets('folder button shows a flat list and restores collapsed groups', (
    WidgetTester tester,
  ) async {
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

    expect(find.text('PUBLIC CHANNELS'), findsOneWidget);
    expect(find.text('DIRECT MESSAGES'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('channel-section-marker-direct')),
      findsOneWidget,
    );
    expect(find.text('Town Square'), findsNothing);

    await tester.tap(find.byTooltip('Hide folder headings'));
    await tester.pumpAndSettle();
    expect(find.text('PUBLIC CHANNELS'), findsNothing);
    expect(find.text('DIRECT MESSAGES'), findsNothing);
    expect(find.text('Town Square'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Grace Hopper'), findsOneWidget);

    await tester.tap(find.byTooltip('Show folder headings'));
    await tester.pumpAndSettle();
    expect(find.text('PUBLIC CHANNELS'), findsOneWidget);
    expect(find.text('DIRECT MESSAGES'), findsOneWidget);
    expect(find.text('Town Square'), findsNothing);
  });

  testWidgets(
    'two sidebar buttons fit the narrowest pane at large text scale',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_SignedInRepository()),
            channelRepositoryProvider.overrideWithValue(
              _UnreadSidebarRepository(),
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

      await tester.drag(
        find.byKey(const ValueKey<String>('channels-pane-divider')),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.byKey(const ValueKey<String>('channels-side-pane')))
            .width,
        200,
      );
      expect(find.byTooltip('Hide read channels'), findsOneWidget);
      expect(find.byTooltip('Hide folder headings'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey<String>('channel-search-field')),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Hide folder headings'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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

    expect(find.text('MUTED CATEGORY'), findsOneWidget);
    expect(find.text('Quiet channel'), findsNothing);
    expect(find.text('Unread in category'), findsNothing);
    expect(
      tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.text('MUTED CATEGORY'),
              matching: find.byType(Opacity),
            ),
          )
          .any((Opacity opacity) => opacity.opacity == 0.55),
      isTrue,
    );

    await tester.tap(find.text('MUTED CATEGORY'));
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

  testWidgets('collapsed folders hide channels and mark unread activity', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final Size size in <Size>[
      const Size(390, 844),
      const Size(1000, 800),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_SignedInRepository()),
            channelRepositoryProvider.overrideWithValue(
              _UnreadSidebarRepository(),
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
      expect(find.text('Muted unread channel'), findsOneWidget);
      await tester.tap(find.text('CHANNELS'));
      await tester.pumpAndSettle();
      expect(find.text('Unread channel'), findsNothing);
      expect(find.text('Muted unread channel'), findsNothing);
      expect(find.text('Muted mentioned channel'), findsNothing);
      expect(find.text('Read channel'), findsNothing);
      final Finder dot = find.byKey(
        const ValueKey<String>('channel-section-unread-dot-channels'),
      );
      expect(dot, findsOneWidget);
      expect(
        tester.widget<Text>(find.text('CHANNELS')).semanticsLabel,
        'Channels, unread',
      );
      expect(
        tester.getRect(dot).right,
        greaterThan(tester.getRect(find.text('CHANNELS')).right),
      );
      await tester.tap(find.text('CHANNELS'));
      await tester.pumpAndSettle();
      expect(find.text('Muted unread channel'), findsOneWidget);
    }
  });

  testWidgets('hides the selected channel in a collapsed category', (
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
    await tester.tap(find.text('MUTED CATEGORY'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unread in category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MUTED CATEGORY'));
    await tester.pumpAndSettle();
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(ChannelSidebar)),
    );
    final channel = container
        .read(channelSidebarProvider)
        .requireValue
        .snapshot
        .sections
        .single
        .channels
        .first;
    expect(channel.isUnread, isFalse);
    expect(
      find.byKey(const ValueKey<String>('channel-unread-category')),
      findsNothing,
    );
    expect(find.text('Quiet channel'), findsNothing);

    container
        .read(selectedChannelProvider.notifier)
        .select(
          const SidebarChannel(
            id: 'quiet',
            teamId: 'team-1',
            name: 'quiet',
            displayName: 'Quiet channel',
            kind: ChannelKind.publicChannel,
          ),
        );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('channel-quiet')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('channel-unread-category')),
      findsNothing,
    );
    await tester.tap(find.text('MUTED CATEGORY'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('channel-quiet')), findsOneWidget);
  });

  testWidgets('keeps category toggles local when the server rejects updates', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _CollapsedMutedSidebarRepository repository =
        _CollapsedMutedSidebarRepository(failUpdate: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('MUTED CATEGORY'));
    await tester.pumpAndSettle();
    expect(repository.lastCollapsed, isFalse);
    expect(find.text('Quiet channel'), findsOneWidget);
    expect(find.text('Unread in category'), findsOneWidget);
    expect(
      find.text('Category changed locally; could not sync with server.'),
      findsOneWidget,
    );
    await tester.tap(find.text('MUTED CATEGORY'));
    await tester.pumpAndSettle();
    expect(repository.lastCollapsed, isTrue);
    expect(find.text('Quiet channel'), findsNothing);
    await tester.tap(find.text('MUTED CATEGORY'));
    await tester.pumpAndSettle();
    expect(find.text('Quiet channel'), findsOneWidget);
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
    expect(find.text('FAVORITES'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.byTooltip('Hide read channels'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide read channels'));
    await tester.pumpAndSettle();
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('channel-favorite-star-town-square')),
      findsOneWidget,
    );
    expect(find.byTooltip('Refresh channels'), findsNothing);
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey<String>('channel-section-surface-favorites'),
            ),
          )
          .height,
      greaterThanOrEqualTo(40),
    );
    final Finder channelTile = find.ancestor(
      of: find.text('Ada Lovelace'),
      matching: find.byType(ListTile),
    );
    expect(tester.getSize(channelTile).height, greaterThanOrEqualTo(40));
    expect(tester.takeException(), isNull);
  });
}

final class _SignedOutRepository implements AuthRepository {
  _SignedOutRepository({Future<AuthSession?>? restoration})
    : _restoration = restoration ?? Future<AuthSession?>.value(null);

  final Future<AuthSession?> _restoration;

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
  Future<AuthSession?> restoreSession() => _restoration;

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
  const _ThreadRepository({this.longThread = false, this.onMarkRead});

  final bool longThread;
  final void Function(String)? onMarkRead;

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
  }) async => onMarkRead?.call(rootPostId);

  @override
  Future<FollowedThreadsPage> loadFollowed({
    required AuthSession session,
    required String teamId,
    String? before,
  }) async {
    FollowedThread thread({
      required String id,
      required String message,
      required int unreadReplies,
    }) => FollowedThread(
      root: ChannelPost(
        id: id,
        channelId: 'town-square',
        author: const PostAuthor(id: 'grace', displayName: 'Grace Hopper'),
        sentAt: DateTime(2026, 8, 24, 10, 30),
        message: message,
        replyCount: 2,
      ),
      replyCount: 2,
      lastReplyAt: DateTime(2026, 8, 24, 10, 35),
      lastViewedAt: DateTime(2026, 8, 24, 10, 32),
      unreadReplies: unreadReplies,
      unreadMentions: unreadReplies > 0 ? 1 : 0,
      participants: const <PostAuthor>[
        PostAuthor(id: 'ada', displayName: 'Ada Lovelace'),
      ],
    );

    return FollowedThreadsPage(
      items: <FollowedThread>[
        thread(
          id: 'unread-root',
          message: 'Unread followed thread',
          unreadReplies: 2,
        ),
        thread(
          id: 'read-root',
          message: 'Read followed thread',
          unreadReplies: 0,
        ),
      ],
      total: 2,
      totalUnreadThreads: 1,
      totalUnreadMentions: 1,
      hasMore: false,
      nextBefore: 'read-root',
    );
  }
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

final class _FailingSidebarPreferencesRepository
    implements SidebarViewPreferencesRepository {
  @override
  Future<SidebarViewPreferences> read(String accountScopeId) async =>
      const SidebarViewPreferences();

  @override
  Future<void> write(
    String accountScopeId,
    SidebarViewPreferences preferences,
  ) async => throw StateError('storage failed');
}

final class _CurrentProfileRepository implements CurrentUserProfileRepository {
  UserPresence? lastPresence;
  DateTime? lastAvailabilityExpiry;
  String? lastCustomStatusText;
  bool failAvailability = false;

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
  }) async {
    if (failAvailability) throw StateError('status unavailable');
    lastPresence = presence;
    lastAvailabilityExpiry = expiresAt;
    return Availability(presence: presence, expiresAt: expiresAt);
  }

  @override
  Future<void> setCustomStatus({
    required String emoji,
    required String text,
    required CustomStatusDuration duration,
    required DateTime expiresAt,
  }) async {
    lastCustomStatusText = text;
  }

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
            favorites: true,
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

final class _CustomStatusSidebarRepository implements ChannelRepository {
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
            id: 'direct',
            displayName: 'Direct Messages',
            role: SidebarSectionRole.directMessages,
            channels: <SidebarChannel>[
              SidebarChannel(
                id: 'direct-ada',
                teamId: '',
                name: 'me__ada',
                displayName: 'Ada Lovelace',
                kind: ChannelKind.directMessage,
                customStatus: UserCustomStatus(
                  emoji: 'calendar',
                  text: 'In a meeting',
                ),
              ),
              SidebarChannel(
                id: 'bot',
                teamId: '',
                name: 'me__bot',
                displayName: 'Helper bot',
                kind: ChannelKind.directMessage,
                isBot: true,
                customStatus: UserCustomStatus(
                  emoji: 'calendar',
                  text: 'Should stay hidden',
                ),
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
            favorites: true,
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
            role: SidebarSectionRole.directMessages,
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
      reason: InboxAttentionReason.groupMention,
      groupMentionHandle: '@dev-team',
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

final class _DeferredInboxTestRepository extends InboxRepository {
  final Completer<InboxSnapshot> snapshot = Completer<InboxSnapshot>();
  var loadCalls = 0;

  @override
  Future<InboxCounters> loadCounters({required AuthSession session}) async =>
      const InboxCounters(newMessages: 2, postponedMessages: 1);

  @override
  Future<InboxSnapshot> load({required AuthSession session}) {
    loadCalls++;
    return snapshot.future;
  }

  @override
  Future<void> markRead({
    required AuthSession session,
    required InboxItem item,
  }) async {}
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

final class _CollapsedMutedSidebarRepository
    implements
        ChannelRepository,
        ChannelSidebarCategoryRepository,
        ChannelSidebarRealtimeRepository {
  _CollapsedMutedSidebarRepository({this.failUpdate = false});
  final bool failUpdate;
  bool? lastCollapsed;

  @override
  Stream<ChannelSidebarRealtimeEvent> watchSidebar({
    required AuthSession session,
  }) => const Stream<ChannelSidebarRealtimeEvent>.empty();

  @override
  Future<void> markChannelViewed({
    required AuthSession session,
    required String channelId,
    String? previousChannelId,
  }) async {}

  @override
  Future<void> setCategoryCollapsed({
    required AuthSession session,
    required String teamId,
    required String categoryId,
    required bool collapsed,
  }) async {
    lastCollapsed = collapsed;
    if (failUpdate) throw StateError('failed');
  }

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
            serverCategory: true,
            collapsed: true,
            muted: true,
            channels: <SidebarChannel>[
              SidebarChannel(
                id: 'unread-category',
                teamId: 'team-1',
                name: 'unread-category',
                displayName: 'Unread in category',
                kind: ChannelKind.publicChannel,
                isUnread: true,
              ),
              SidebarChannel(
                id: 'quiet',
                teamId: 'team-1',
                name: 'quiet',
                displayName: 'Quiet channel',
                kind: ChannelKind.publicChannel,
              ),
              SidebarChannel(
                id: 'mention-category',
                teamId: 'team-1',
                name: 'mention-category',
                displayName: 'Mention in category',
                kind: ChannelKind.publicChannel,
                isUnread: true,
                hasUnreadMention: true,
              ),
            ],
          ),
        ],
      );
}

final class _ReadFilterSidebarRepository
    implements ChannelRepository, ChannelSidebarActionsRepository {
  String? lastAction;

  @override
  Future<List<SidebarSection>> getMovableCategories(
    AuthSession session,
    String teamId,
  ) async => const <SidebarSection>[
    SidebarSection(
      id: 'empty',
      displayName: 'Empty folder',
      channels: <SidebarChannel>[],
      serverCategory: true,
    ),
    SidebarSection(
      id: 'mixed',
      displayName: 'Mixed',
      channels: <SidebarChannel>[],
      serverCategory: true,
    ),
  ];

  @override
  Future<void> markChannelUnread(AuthSession session, String channelId) async =>
      lastAction = 'unread:$channelId';

  @override
  Future<void> setChannelFavorite(
    AuthSession session,
    String teamId,
    SidebarChannel channel,
    bool favorite,
  ) async => lastAction = 'favorite:${channel.id}:$favorite';

  @override
  Future<void> setChannelMuted(
    AuthSession session,
    String channelId,
    bool muted,
  ) async => lastAction = 'mute:$channelId:$muted';

  @override
  Future<void> moveChannelToCategory(
    AuthSession session,
    String teamId,
    String channelId,
    String categoryId,
  ) async => lastAction = 'move:$channelId:$categoryId';

  @override
  Future<void> closeConversation(
    AuthSession session,
    SidebarChannel channel,
  ) async => lastAction = 'close:${channel.id}';

  @override
  Future<void> leaveChannel(
    AuthSession session,
    SidebarChannel channel,
  ) async => lastAction = 'leave:${channel.id}';

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
            id: 'empty',
            displayName: 'Empty',
            channels: <SidebarChannel>[],
          ),
          SidebarSection(
            id: 'mixed',
            displayName: 'Mixed',
            channels: <SidebarChannel>[
              SidebarChannel(
                id: 'unread',
                teamId: 'team-1',
                name: 'unread',
                displayName: 'Unread channel',
                kind: ChannelKind.publicChannel,
                isUnread: true,
              ),
              SidebarChannel(
                id: 'read',
                teamId: 'team-1',
                name: 'read',
                displayName: 'Read channel',
                kind: ChannelKind.publicChannel,
              ),
            ],
          ),
          SidebarSection(
            id: 'read-only',
            displayName: 'Read only',
            channels: <SidebarChannel>[
              SidebarChannel(
                id: 'read-only-channel',
                teamId: 'team-1',
                name: 'read-only-channel',
                displayName: 'Read only channel',
                kind: ChannelKind.publicChannel,
              ),
            ],
          ),
        ],
      );
}

final class _UnreadSidebarRepository implements ChannelRepository {
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
            id: 'channels',
            displayName: 'Channels',
            channels: <SidebarChannel>[
              SidebarChannel(
                id: 'unread',
                teamId: 'team-1',
                name: 'unread',
                displayName: 'Unread channel',
                kind: ChannelKind.publicChannel,
                isUnread: true,
              ),
              SidebarChannel(
                id: 'read',
                teamId: 'team-1',
                name: 'read',
                displayName: 'Read channel',
                kind: ChannelKind.publicChannel,
              ),
              SidebarChannel(
                id: 'muted-unread',
                teamId: 'team-1',
                name: 'muted-unread',
                displayName: 'Muted unread channel',
                kind: ChannelKind.publicChannel,
                isUnread: true,
                muted: true,
              ),
              SidebarChannel(
                id: 'muted-mentioned',
                teamId: 'team-1',
                name: 'muted-mentioned',
                displayName: 'Muted mentioned channel',
                kind: ChannelKind.publicChannel,
                isUnread: true,
                hasUnreadMention: true,
                muted: true,
              ),
            ],
          ),
        ],
      );
}

final class _ChannelMembersRepository implements ChannelMembersRepository {
  const _ChannelMembersRepository();

  @override
  Future<int> getCount(String channelId) async => 2;

  @override
  Future<ChannelMembersPage> loadPage({
    required String channelId,
    required int page,
    required int perPage,
  }) async => ChannelMembersPage(
    members: <ChannelMember>[
      ChannelMember(
        user: UserSummary(
          id: 'ada',
          firstName: 'Ada',
          lastName: 'Lovelace',
          username: 'ada',
          nickname: '',
          position: '',
          email: '',
          profileImageUpdatedAt: 99,
        ),
        isChannelAdmin: true,
      ),
      ChannelMember(
        user: UserSummary(
          id: 'grace',
          firstName: 'Grace',
          lastName: 'Hopper',
          username: 'grace',
          nickname: '',
          position: '',
          email: '',
          profileImageUpdatedAt: 99,
        ),
      ),
    ],
  );
}
