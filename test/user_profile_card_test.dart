import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mattermost_flutter/src/app/di/app_providers.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message.dart';
import 'package:mattermost_flutter/src/features/messages/presentation/message_primitives.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_profile.dart';
import 'package:mattermost_flutter/src/features/users/presentation/user_profile_card.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('ru'));

  const UserProfile profile = UserProfile(
    id: 'ada',
    firstName: 'Ada',
    lastName: 'Lovelace',
    username: 'ada',
    nickname: 'ada-nickname',
    position: 'Mathematician',
    email: 'ada@example.com',
    presence: UserPresence.online,
    profileImageUpdatedAt: 42,
  );
  final AuthSession session = AuthSession(
    serverUrl: Uri.parse('https://chat.example.com'),
    userId: 'me',
    username: 'me',
  );

  testWidgets(
    'renders the requested profile fields and opens a direct message',
    (WidgetTester tester) async {
      UserProfile? messagedProfile;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWithValue(session),
            userProfileProvider.overrideWith(
              (Ref ref, String userId) async => profile,
            ),
            userAvatarProvider.overrideWith(
              (Ref ref, UserAvatarRequest input) async => null,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: UserProfileCard(
                userId: 'ada',
                onMessage: (UserProfile value) async {
                  messagedProfile = value;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('@ada-nickname'), findsOneWidget);
      expect(find.text('Mathematician'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('ada@example.com'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Message'));
      await tester.pumpAndSettle();
      expect(messagedProfile, same(profile));
    },
  );

  testWidgets('opens the card from the avatar only', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(session),
          userProfileProvider.overrideWith(
            (Ref ref, String userId) async => profile,
          ),
          userAvatarProvider.overrideWith(
            (Ref ref, UserAvatarRequest input) async => null,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                const MessageAvatar(
                  author: PostAuthor(id: 'ada', displayName: 'Ada Lovelace'),
                ),
                MessageAuthorLine(
                  author: const PostAuthor(
                    id: 'ada',
                    displayName: 'Ada Lovelace',
                  ),
                  sentAt: DateTime(2026),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(MessageAvatar));
    await tester.pumpAndSettle();
    expect(find.byType(UserProfileCard), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ada Lovelace').last);
    await tester.pumpAndSettle();
    expect(find.byType(UserProfileCard), findsNothing);
  });

  test('formats post times in 24-hour format with dates for earlier days', () {
    final DateTime now = DateTime(2026, 8, 31, 12);

    expect(
      formatMessageTimestamp(
        sentAt: DateTime(2026, 8, 31, 10, 20),
        locale: 'ru',
        now: now,
      ),
      '10:20',
    );
    expect(
      formatMessageTimestamp(
        sentAt: DateTime(2026, 8, 30, 10, 20),
        locale: 'ru',
        now: now,
      ),
      '30 авг 10:20',
    );
  });

  testWidgets('shows loading and an explicit retry state', (
    WidgetTester tester,
  ) async {
    final Completer<UserProfile> completer = Completer<UserProfile>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(session),
          userProfileProvider.overrideWith(
            (Ref ref, String userId) => completer.future,
          ),
        ],
        child: MaterialApp(
          home: UserProfileCard(
            userId: 'ada',
            onMessage: (UserProfile value) async {},
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load this user profile.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
  });

  testWidgets('fits compact width with large text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(session),
          userProfileProvider.overrideWith(
            (Ref ref, String userId) async => profile,
          ),
          userAvatarProvider.overrideWith(
            (Ref ref, UserAvatarRequest input) async => null,
          ),
        ],
        child: MaterialApp(
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: UserProfileCard(
            userId: 'ada',
            onMessage: (UserProfile value) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Ada Lovelace'), findsOneWidget);
  });
}
