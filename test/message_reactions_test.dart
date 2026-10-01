import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/providers/repository_providers.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_interaction_surface.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';

import 'support/fake_user_repository.dart';

void main() {
  const String tooltip =
      'Ada Lovelace, Grace Hopper\n'
      'Alan Turing, Margaret Hamilton\n'
      'Linus Torvalds\n'
      'reacted with 👍';

  testWidgets('shows reactor display names when a mouse hovers the reaction', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(onToggle: (_) async {}));
    await tester.pump();

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(_reaction));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text(tooltip), findsOneWidget);
    await mouse.removePointer();
  });

  testWidgets('touch tap toggles the reaction without opening its tooltip', (
    WidgetTester tester,
  ) async {
    var toggles = 0;
    await tester.pumpWidget(_app(onToggle: (_) async => toggles += 1));
    await tester.pump();

    await tester.tap(_reaction, kind: PointerDeviceKind.touch);
    await tester.pump();

    expect(toggles, 1);
    expect(find.text(tooltip), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('message-actions-bottom-sheet')),
      findsNothing,
    );
  });

  testWidgets(
    'touch long press shows reactor names with haptics and no message sheet',
    (WidgetTester tester) async {
      var toggles = 0;
      final List<MethodCall> platformCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          platformCalls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(_app(onToggle: (_) async => toggles += 1));
      await tester.pump();

      final TestGesture touch = await tester.startGesture(
        tester.getCenter(_reaction),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      expect(find.text(tooltip), findsOneWidget);
      expect(toggles, 0);
      expect(
        find.byKey(const ValueKey<String>('message-actions-bottom-sheet')),
        findsNothing,
      );
      expect(
        platformCalls.where(
          (MethodCall call) => call.method == 'HapticFeedback.vibrate',
        ),
        isNotEmpty,
      );

      await touch.up();
      await tester.pumpAndSettle();
      expect(toggles, 0);
    },
  );

  testWidgets('tooltip supports compact width with large text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        onToggle: (_) async {},
        textScaler: const TextScaler.linear(2),
        width: 320,
      ),
    );
    await tester.pump();

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(_reaction));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text(tooltip), findsOneWidget);
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  });
}

Finder get _reaction => find.byKey(const ValueKey<String>('reaction-thumbsup'));

Widget _app({
  required Future<void> Function(PostReaction reaction) onToggle,
  TextScaler textScaler = TextScaler.noScaling,
  double? width,
}) {
  final FakeUserRepository users = FakeUserRepository(
    users: const <String, UserSummary>{
      'ada': UserSummary(
        id: 'ada',
        firstName: 'Ada',
        lastName: 'Lovelace',
        username: 'ada',
        nickname: '',
        position: '',
        email: '',
      ),
      'grace': UserSummary(
        id: 'grace',
        firstName: 'Grace',
        lastName: 'Hopper',
        username: 'grace',
        nickname: '',
        position: '',
        email: '',
      ),
      'alan': UserSummary(
        id: 'alan',
        firstName: 'Alan',
        lastName: 'Turing',
        username: 'alan',
        nickname: '',
        position: '',
        email: '',
      ),
      'margaret': UserSummary(
        id: 'margaret',
        firstName: 'Margaret',
        lastName: 'Hamilton',
        username: 'margaret',
        nickname: '',
        position: '',
        email: '',
      ),
      'linus': UserSummary(
        id: 'linus',
        firstName: 'Linus',
        lastName: 'Torvalds',
        username: 'linus',
        nickname: '',
        position: '',
        email: '',
      ),
    },
  );
  final Post post = Post(
    id: 'post-1',
    channelId: 'channel-1',
    author: const PostAuthor(id: 'ada', displayName: 'Ada Lovelace'),
    sentAt: DateTime.fromMillisecondsSinceEpoch(1),
    message: 'Hello',
    reactions: const <PostReaction>[
      PostReaction(
        emoji: '👍',
        emojiName: 'thumbsup',
        count: 5,
        userIds: <String>['ada', 'grace', 'alan', 'margaret', 'linus'],
      ),
    ],
  );
  return MediaQuery(
    data: MediaQueryData(textScaler: textScaler),
    child: ProviderScope(
      overrides: [userRepositoryProvider.overrideWithValue(users)],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: MessageInteractionSurface(
                onOpenThread: () {},
                child: MessageReactions(
                  post: post,
                  semanticsLabel: 'Reactions',
                  onToggle: onToggle,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
