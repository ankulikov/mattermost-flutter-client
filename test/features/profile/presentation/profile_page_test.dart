import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/profile/domain/models/current_user_profile.dart';
import 'package:mattermost_flutter/src/features/profile/domain/repositories/current_user_profile_repository.dart';
import 'package:mattermost_flutter/src/features/profile/presentation/profile_page.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  final AuthSession session = AuthSession(
    serverUrl: Uri.parse('https://chat.example.com'),
    userId: 'me',
    username: 'ada',
  );

  Future<void> pumpProfile(
    WidgetTester tester,
    _ProfileRepository repository, {
    double textScale = 1,
    Future<void> Function()? onLogout,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(session),
          currentUserProfileRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: ProfilePage(onLogout: onLogout ?? () async {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('asks for expiry only for DND and keeps it synchronized', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _ProfileRepository repository = _ProfileRepository();
    await pumpProfile(tester, repository);

    expect(
      find.byKey(const ValueKey<String>('availability-doNotDisturb')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('availability-away')));
    await tester.pumpAndSettle();
    expect(find.text('Clear after'), findsNothing);
    expect(repository.lastPresence, UserPresence.away);
    expect(repository.lastAvailabilityExpiry, isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('availability-doNotDisturb')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Clear after'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('availability-expiry-thirtyMinutes')),
    );
    await tester.pumpAndSettle();

    expect(repository.lastPresence, UserPresence.doNotDisturb);
    expect(repository.lastAvailabilityExpiry, isNotNull);
    expect(
      find.byKey(const ValueKey<String>('availability-doNotDisturb')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('availability-expiry')), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('highlights a matching quick status and reapplies it', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final _ProfileRepository repository = _ProfileRepository();
    await pumpProfile(tester, repository);

    final FilterChip meeting = tester.widget<FilterChip>(
      find.byKey(const ValueKey<String>('quick-status-calendar')),
    );
    final FilterChip commuting = tester.widget<FilterChip>(
      find.byKey(const ValueKey<String>('quick-status-bus')),
    );
    expect(meeting.selected, isTrue);
    expect(meeting.showCheckmark, isFalse);
    expect(commuting.selected, isFalse);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('quick-status-calendar')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('quick-status-calendar')),
    );
    await tester.pumpAndSettle();

    expect(repository.customStatusSetCalls, 1);
    expect(repository.lastCustomText, 'In a meeting');
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey<String>('quick-status-calendar')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey<String>('quick-status-calendar')),
          )
          .showCheckmark,
      isFalse,
    );
  });

  testWidgets('keeps all availability choices in one compact row', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpProfile(tester, _ProfileRepository());

    final Finder online = find.byKey(
      const ValueKey<String>('availability-online'),
    );
    final Finder away = find.byKey(const ValueKey<String>('availability-away'));
    final Finder dnd = find.byKey(
      const ValueKey<String>('availability-doNotDisturb'),
    );
    final Finder offline = find.byKey(
      const ValueKey<String>('availability-offline'),
    );

    expect(find.text('DnD'), findsOneWidget);
    expect(tester.getTopLeft(online).dy, tester.getTopLeft(away).dy);
    expect(tester.getTopLeft(away).dy, tester.getTopLeft(dnd).dy);
    expect(tester.getTopLeft(dnd).dy, tester.getTopLeft(offline).dy);
    expect(
      tester
          .widget<Material>(
            find.ancestor(of: online, matching: find.byType(Material)).first,
          )
          .shape,
      isA<RoundedRectangleBorder>(),
    );
  });

  testWidgets('places the identity directly below the avatar before statuses', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpProfile(tester, _ProfileRepository());

    final double avatarBottom = tester
        .getBottomRight(
          find.byKey(const ValueKey<String>('profile-header-presence')),
        )
        .dy;
    final double nameTop = tester.getTopLeft(find.text('Ada Lovelace')).dy;
    final double usernameTop = tester.getTopLeft(find.text('@ada')).dy;
    final double presenceTop = tester
        .getTopLeft(find.text('Do not disturb'))
        .dy;
    final double customStatusTop = tester
        .getTopLeft(find.byKey(const ValueKey<String>('current-custom-status')))
        .dy;

    expect(nameTop, greaterThan(avatarBottom));
    expect(usernameTop, greaterThan(nameTop));
    expect(presenceTop, greaterThan(usernameTop));
    expect(customStatusTop, greaterThan(presenceTop));
  });

  testWidgets('sets and clears quick custom status and logs out', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _ProfileRepository repository = _ProfileRepository();
    var logoutCalls = 0;
    await pumpProfile(
      tester,
      repository,
      onLogout: () async => logoutCalls += 1,
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('profile-scroll-view')),
        matching: find.byKey(const ValueKey<String>('profile-logout')),
      ),
      findsOneWidget,
    );
    final Finder logout = find.byKey(const ValueKey<String>('profile-logout'));
    final ListTile logoutTile = tester.widget<ListTile>(logout);
    expect(
      logoutTile.textColor,
      Theme.of(tester.element(logout)).colorScheme.error,
    );
    expect(
      find.descendant(of: logout, matching: find.byIcon(Icons.chevron_right)),
      findsNothing,
    );

    await tester.tap(find.byTooltip('Clear custom status'));
    await tester.pumpAndSettle();
    expect(repository.clearCalls, 1);
    expect(
      find.byKey(const ValueKey<String>('current-custom-status')),
      findsNothing,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('quick-status-bus')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('quick-status-bus')));
    await tester.pumpAndSettle();
    expect(repository.lastCustomText, 'Commuting');
    expect(repository.lastCustomDuration, CustomStatusDuration.oneHour);
    expect(find.text('Commuting'), findsWidgets);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('quick-status-palm_tree')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('quick-status-palm_tree')),
    );
    await tester.pumpAndSettle();
    expect(repository.lastCustomText, 'Day off');
    expect(repository.lastCustomDuration, CustomStatusDuration.oneDay);
    expect(find.text('1 day'), findsOneWidget);

    final Finder profileScrollable = find.descendant(
      of: find.byKey(const ValueKey<String>('profile-scroll-view')),
      matching: find.byType(Scrollable),
    );
    await tester.drag(profileScrollable, const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(logout);
    await tester.pumpAndSettle();
    expect(logoutCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adapts at expanded width and large text scale', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpProfile(tester, _ProfileRepository(), textScale: 2);

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('availability-online')), findsOne);
    expect(
      find.byKey(const ValueKey<String>('quick-status-calendar')),
      findsOne,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens Display settings from the enabled profile tile', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpProfile(tester, _ProfileRepository());

    final Finder displaySettings = find.byKey(
      const ValueKey<String>('profile-display-settings'),
    );
    await tester.drag(
      find.byKey(const ValueKey<String>('profile-scroll-view')),
      const Offset(0, -800),
    );
    await tester.pumpAndSettle();
    final ListTile displayTile = tester.widget<ListTile>(displaySettings);
    expect(displayTile.enabled, isTrue);

    await tester.tap(displaySettings);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('display-settings-page')),
      findsOneWidget,
    );
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an initial retry state without profile data', (
    WidgetTester tester,
  ) async {
    final _ProfileRepository repository = _ProfileRepository(failLoad: true);
    await pumpProfile(tester, repository);

    expect(find.text('Could not load your profile.'), findsOneWidget);
    repository.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preserves the selected status when an update fails', (
    WidgetTester tester,
  ) async {
    final _ProfileRepository repository = _ProfileRepository(
      failAvailabilityUpdate: true,
    );
    await pumpProfile(tester, repository);

    await tester.tap(find.byKey(const ValueKey<String>('availability-away')));
    await tester.pumpAndSettle();

    expect(find.text('Could not update your status.'), findsOneWidget);
    final Container presenceIndicator = tester.widget<Container>(
      find.byKey(const ValueKey<String>('profile-header-presence')),
    );
    final BoxDecoration decoration =
        presenceIndicator.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xffd24b4e));
    expect(tester.takeException(), isNull);
  });
}

final class _ProfileRepository implements CurrentUserProfileRepository {
  _ProfileRepository({
    this.failLoad = false,
    this.failAvailabilityUpdate = false,
  });

  bool failLoad;
  final bool failAvailabilityUpdate;
  UserPresence? lastPresence;
  DateTime? lastAvailabilityExpiry;
  String? lastCustomText;
  CustomStatusDuration? lastCustomDuration;
  int clearCalls = 0;
  int customStatusSetCalls = 0;

  @override
  Future<CurrentUserProfile> load() async {
    if (failLoad) throw StateError('load failed');
    return CurrentUserProfile(
      user: const UserSummary(
        id: 'me',
        firstName: 'Ada',
        lastName: 'Lovelace',
        username: 'ada',
        nickname: '',
        position: '',
        email: 'ada@example.com',
      ),
      availability: Availability(
        presence: UserPresence.doNotDisturb,
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      ),
      customStatus: CustomStatus(
        emoji: 'calendar',
        text: 'In a meeting',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
  }

  @override
  Future<Availability> setAvailability({
    required UserPresence presence,
    required DateTime? expiresAt,
  }) async {
    if (failAvailabilityUpdate) throw StateError('update failed');
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
    customStatusSetCalls += 1;
    lastCustomText = text;
    lastCustomDuration = duration;
  }

  @override
  Future<void> clearCustomStatus() async => clearCalls += 1;
}
