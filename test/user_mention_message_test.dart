import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/models/user_mention.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/group_mention.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';
import 'package:mattermost_flutter/src/ui/users/widgets/user_profile_card.dart';

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

    expect(
      find.textContaining('@Ada Lovelace', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('@missing'), findsOneWidget);

    _tapTextSpan(tester, '@Ada Lovelace');
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

    expect(
      find.textContaining('@Ada Lovelace', findRichText: true),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps resolved full names within table rows', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final Completer<List<UserMention>> mentions =
        Completer<List<UserMention>>();
    const String message = '''
| Priority | PR | Waiting | Responsible |
| --- | --- | --- | --- |
| warning | first | 6h | @andrey @ilya @vladislav |
| warning | second | 5h | @ruslan @nikita @semen |
''';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userMentionsProvider(
            userMentionLookupKey(message),
          ).overrideWith((Ref ref) => mentions.future),
        ],
        child: MaterialApp(
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(body: _messageBody(message)),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('@andrey', findRichText: true), findsOneWidget);
    mentions.complete(const <UserMention>[
      UserMention(
        userId: 'andrey-id',
        username: 'andrey',
        displayName: 'Andrey Petrov',
      ),
      UserMention(
        userId: 'ilya-id',
        username: 'ilya',
        displayName: 'Ilya Edrets',
      ),
      UserMention(
        userId: 'vladislav-id',
        username: 'vladislav',
        displayName: 'Vladislav Sychev',
      ),
      UserMention(
        userId: 'ruslan-id',
        username: 'ruslan',
        displayName: 'Ruslan Azamatov',
      ),
      UserMention(
        userId: 'nikita-id',
        username: 'nikita',
        displayName: 'Nikita Khramov',
      ),
      UserMention(
        userId: 'semen-id',
        username: 'semen',
        displayName: 'Semen Sychev',
      ),
    ]);
    await tester.pumpAndSettle();

    final RenderTable resolvedTable = tester.renderObject<RenderTable>(
      find.byType(Table),
    );
    final Rect firstRow = resolvedTable
        .getRowBox(1)
        .shift(resolvedTable.localToGlobal(Offset.zero));
    final Rect secondRow = resolvedTable
        .getRowBox(2)
        .shift(resolvedTable.localToGlobal(Offset.zero));
    for (final String displayName in <String>[
      '@Andrey Petrov',
      '@Ilya Edrets',
      '@Vladislav Sychev',
    ]) {
      expect(
        tester.getRect(find.textContaining(displayName, findRichText: true)),
        _isContainedVerticallyBy(firstRow),
      );
    }
    for (final String displayName in <String>[
      '@Ruslan Azamatov',
      '@Nikita Khramov',
      '@Semen Sychev',
    ]) {
      expect(
        tester.getRect(find.textContaining(displayName, findRichText: true)),
        _isContainedVerticallyBy(secondRow),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a resolved mention as wrapping inline text', (
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

    final Finder richText = find.textContaining(
      '@Ada Lovelace',
      findRichText: true,
    );
    expect(richText, findsOneWidget);
    final InlineSpan span = tester.widget<RichText>(richText).text;
    expect(_findTapRecognizer(span, '@Ada Lovelace'), isNotNull);
    expect(_containsWidgetSpan(span), isFalse);
  });

  testWidgets('keeps a resolved group handle unchanged and tap is a no-op', (
    WidgetTester tester,
  ) async {
    const String message = 'Hello @backend';
    final String lookupKey = userMentionLookupKey(message);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userMentionsProvider(lookupKey).overrideWithValue(
            const AsyncValue<List<UserMention>>.data(<UserMention>[]),
          ),
          groupMentionsProvider(lookupKey).overrideWithValue(
            const AsyncValue<List<GroupMention>>.data(<GroupMention>[
              GroupMention(
                id: 'backend-id',
                name: 'backend',
                displayName: 'Backend Team',
                memberCount: 18,
              ),
            ]),
          ),
        ],
        child: MaterialApp(home: Scaffold(body: _messageBody(message))),
      ),
    );
    await tester.pumpAndSettle();

    final Finder richText = find.textContaining('@backend', findRichText: true);
    expect(richText, findsOneWidget);
    final InlineSpan span = tester.widget<RichText>(richText).text;
    expect(_findTapRecognizer(span, '@backend'), isNotNull);

    _tapTextSpan(tester, '@backend');
    await tester.pump();
    expect(find.byType(UserProfileCard), findsNothing);
    expect(tester.takeException(), isNull);
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

Matcher _isContainedVerticallyBy(Rect outer) => predicate<Rect>(
  (Rect inner) =>
      inner.top >= outer.top - 0.01 && inner.bottom <= outer.bottom + 0.01,
  'is vertically contained by $outer',
);

bool _containsWidgetSpan(InlineSpan span) {
  if (span is WidgetSpan) return true;
  return span is TextSpan && span.children?.any(_containsWidgetSpan) == true;
}

void _tapTextSpan(WidgetTester tester, String text) {
  final Iterable<InlineSpan> spans = <InlineSpan>[
    ...find
        .byType(RichText)
        .evaluate()
        .map((Element element) => (element.widget as RichText).text),
    ...find
        .byType(SelectableText)
        .evaluate()
        .map((Element element) => (element.widget as SelectableText).textSpan!),
  ];
  for (final InlineSpan span in spans) {
    final TapGestureRecognizer? recognizer = _findTapRecognizer(span, text);
    if (recognizer != null) {
      recognizer.onTap?.call();
      return;
    }
  }
  fail('No tappable text span contained "$text".');
}

TapGestureRecognizer? _findTapRecognizer(InlineSpan span, String text) {
  if (span is! TextSpan) return null;
  final GestureRecognizer? recognizer = span.recognizer;
  if (span.toPlainText().contains(text) && recognizer is TapGestureRecognizer) {
    return recognizer;
  }
  for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
    final TapGestureRecognizer? recognizer = _findTapRecognizer(child, text);
    if (recognizer != null) return recognizer;
  }
  return null;
}
