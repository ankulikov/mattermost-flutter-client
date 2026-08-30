import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/app/di/app_providers.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message.dart';
import 'package:mattermost_flutter/src/features/messages/presentation/message_primitives.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_mention.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_profile.dart';
import 'package:mattermost_flutter/src/features/users/presentation/user_profile_card.dart';

void main() {
  test('extracts unique user mentions without treating emails as mentions', () {
    expect(
      extractUserMentionNames(
        'Hi @Ada.Lovelace and @grace-hopper; '
        'mail ada@example.com, again @ada.lovelace',
      ),
      <String>['ada.lovelace', 'grace-hopper'],
    );
  });

  testWidgets('shows resolved full name and opens the shared profile card', (
    WidgetTester tester,
  ) async {
    const String message = 'Hello @ada and @missing';
    const UserMention mention = UserMention(
      userId: 'ada-id',
      username: 'ada',
      displayName: 'Ada Lovelace',
    );
    const UserProfile profile = UserProfile(
      id: 'ada-id',
      firstName: 'Ada',
      lastName: 'Lovelace',
      username: 'ada',
      nickname: '',
      position: '',
      email: '',
      presence: UserPresence.online,
    );
    final AuthSession session = AuthSession(
      serverUrl: Uri.parse('https://chat.example.com'),
      userId: 'me',
      username: 'me',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(session),
          userMentionsProvider(userMentionLookupKey(message)).overrideWithValue(
            const AsyncValue<List<UserMention>>.data(<UserMention>[mention]),
          ),
          userProfileProvider.overrideWith(
            (Ref ref, String userId) async => profile,
          ),
          userAvatarProvider.overrideWith(
            (Ref ref, UserAvatarRequest input) async => null,
          ),
        ],
        child: MaterialApp(home: Scaffold(body: _messageBody(message))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('@Ada Lovelace'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('user-mention-ada')),
      findsOneWidget,
    );
    expect(find.textContaining('@missing'), findsOneWidget);

    await tester.tap(find.text('@Ada Lovelace'));
    await tester.pumpAndSettle();
    expect(find.byType(UserProfileCard), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
  });

  testWidgets('keeps usernames unchanged while resolution is unavailable', (
    WidgetTester tester,
  ) async {
    const String message = 'Hello @missing';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userMentionsProvider(userMentionLookupKey(message)).overrideWithValue(
            AsyncValue<List<UserMention>>.error(
              StateError('offline'),
              StackTrace.empty,
            ),
          ),
        ],
        child: MaterialApp(home: Scaffold(body: _messageBody(message))),
      ),
    );
    await tester.pump();

    expect(find.textContaining('@missing'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('user-mention-missing')),
      findsNothing,
    );
  });

  testWidgets('lays out a resolved mention at compact width and large text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const String message = 'Hello @ada';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userMentionsProvider(userMentionLookupKey(message)).overrideWithValue(
            const AsyncValue<List<UserMention>>.data(<UserMention>[
              UserMention(
                userId: 'ada-id',
                username: 'ada',
                displayName: 'Ada Lovelace',
              ),
            ]),
          ),
        ],
        child: MaterialApp(
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(body: _messageBody(message)),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('@Ada Lovelace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('underlines a resolved mention only while hovered', (
    WidgetTester tester,
  ) async {
    const String message = 'Hello @ada';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userMentionsProvider(userMentionLookupKey(message)).overrideWithValue(
            const AsyncValue<List<UserMention>>.data(<UserMention>[
              UserMention(
                userId: 'ada-id',
                username: 'ada',
                displayName: 'Ada Lovelace',
              ),
            ]),
          ),
        ],
        child: MaterialApp(home: Scaffold(body: _messageBody(message))),
      ),
    );
    await tester.pumpAndSettle();

    Text mentionText() => tester.widget<Text>(find.text('@Ada Lovelace'));
    expect(mentionText().style?.decoration, TextDecoration.none);

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.text('@Ada Lovelace')));
    await tester.pump();
    expect(mentionText().style?.decoration, TextDecoration.underline);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(mentionText().style?.decoration, TextDecoration.none);
  });
}

MessageBody _messageBody(String message) => MessageBody(
  post: ChannelPost(
    id: 'post-1',
    channelId: 'channel-1',
    author: const PostAuthor(id: 'author', displayName: 'Author'),
    sentAt: DateTime.fromMillisecondsSinceEpoch(1),
    message: message,
  ),
);
