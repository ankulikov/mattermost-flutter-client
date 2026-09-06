import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/repositories/emoji_repository.dart';
import 'package:mattermost_flutter/src/ui/messages/message_actions_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_interaction_surface.dart';

import 'support/fake_emoji_repository.dart';

void main() {
  testWidgets('touch tap highlights the message and opens its thread', (
    WidgetTester tester,
  ) async {
    var openCount = 0;
    await tester.pumpWidget(_app(onOpenThread: () => openCount += 1));

    await tester.tap(find.text('Message'), kind: PointerDeviceKind.touch);
    await tester.pump();

    expect(openCount, 1);
    final Container highlight = tester.widget(
      find.byKey(const ValueKey<String>('message-highlight')),
    );
    final BoxDecoration decoration = highlight.decoration! as BoxDecoration;
    expect(decoration.color, _expectedHighlightColor(tester));

    await tester.pump(const Duration(milliseconds: 700));
    final Container fadedHighlight = tester.widget(
      find.byKey(const ValueKey<String>('message-highlight')),
    );
    final BoxDecoration fadedDecoration =
        fadedHighlight.decoration! as BoxDecoration;
    expect(fadedDecoration.color, Colors.transparent);
  });

  testWidgets('touch long press opens the message actions bottom sheet', (
    WidgetTester tester,
  ) async {
    var openCount = 0;
    await tester.pumpWidget(_app(onOpenThread: () => openCount += 1));
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

    final TestGesture touch = await tester.startGesture(
      tester.getCenter(find.text('Message')),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 600));

    final Container highlight = tester.widget(
      find.byKey(const ValueKey<String>('message-highlight')),
    );
    final BoxDecoration decoration = highlight.decoration! as BoxDecoration;
    expect(decoration.color, _expectedHighlightColor(tester));
    expect(
      platformCalls,
      contains(
        isA<MethodCall>()
            .having(
              (MethodCall call) => call.method,
              'method',
              'HapticFeedback.vibrate',
            )
            .having(
              (MethodCall call) => call.arguments,
              'type',
              'HapticFeedbackType.lightImpact',
            ),
      ),
    );

    await touch.up();
    await tester.pumpAndSettle();

    expect(openCount, 0);
    expect(
      find.byKey(const ValueKey<String>('message-actions-bottom-sheet')),
      findsOneWidget,
    );
    expect(find.text(MessageActionsStrings.followThread), findsOneWidget);
  });

  testWidgets('mouse click opens thread and hover exposes quick actions', (
    WidgetTester tester,
  ) async {
    var openCount = 0;
    await tester.pumpWidget(_app(onOpenThread: () => openCount += 1));
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);

    await mouse.addPointer(location: tester.getCenter(find.text('Message')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('quick-message-actions')),
      findsOneWidget,
    );
    expect(find.byType(AnimatedContainer), findsNothing);
    final Container highlight = tester.widget(
      find.byKey(const ValueKey<String>('message-highlight')),
    );
    final BoxDecoration decoration = highlight.decoration! as BoxDecoration;
    expect(decoration.color, _expectedHighlightColor(tester));

    await mouse.down(tester.getCenter(find.text('Message')));
    await mouse.up();
    await tester.pump();
    expect(openCount, 1);

    await tester.tap(
      find.byKey(const ValueKey<String>('more-message-actions')),
    );
    await tester.pumpAndSettle();
    expect(openCount, 1);
    expect(find.text(MessageActionsStrings.forward), findsOneWidget);
    expect(find.text(MessageActionsStrings.delete), findsOneWidget);
  });

  testWidgets('mouse long press does not open touch bottom sheet', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(onOpenThread: () {}));

    await tester.longPress(find.text('Message'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('message-actions-bottom-sheet')),
      findsNothing,
    );
  });

  testWidgets('compact hover toolbar fits with large text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        onOpenThread: () {},
        width: 300,
        textScaler: const TextScaler.linear(2),
      ),
    );
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);

    await mouse.addPointer(location: tester.getCenter(find.text('Message')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('quick-message-actions')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('hover add-reaction opens picker and submits selection', (
    WidgetTester tester,
  ) async {
    final FakeEmojiRepository repository = FakeEmojiRepository();
    String? toggled;
    await tester.pumpWidget(
      _app(
        onOpenThread: () {},
        repository: repository,
        onToggleReaction: (String name) async {
          toggled = name;
          return true;
        },
      ),
    );
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.text('Message')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(MessageActionsStrings.addReaction));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('emoji-picker-popover')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('emoji-search-field')),
      'grinning',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('emoji-grinning')));
    await tester.pumpAndSettle();

    expect(toggled, 'grinning');
    expect(repository.remembered, <String>['grinning']);
  });

  testWidgets('touch add-reaction replaces actions sheet with picker', (
    WidgetTester tester,
  ) async {
    final FakeEmojiRepository repository = FakeEmojiRepository()
      ..recent = <String>['thumbsup'];
    String? toggled;
    await tester.pumpWidget(
      _app(
        onOpenThread: () {},
        repository: repository,
        onToggleReaction: (String name) async {
          toggled = name;
          return true;
        },
      ),
    );

    await tester.longPress(find.text('Message'), kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_reaction_outlined).last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('message-actions-bottom-sheet')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('emoji-picker-bottom-sheet')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('emoji-thumbsup')));
    await tester.pumpAndSettle();

    expect(toggled, 'thumbsup');
    expect(repository.remembered, <String>['thumbsup']);
  });
}

Widget _app({
  required VoidCallback onOpenThread,
  double width = 600,
  TextScaler textScaler = TextScaler.noScaling,
  CustomEmojiRepository? repository,
  Future<bool> Function(String emojiName)? onToggleReaction,
}) => MaterialApp(
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: child!,
  ),
  theme: ThemeData(useMaterial3: true),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        child: MessageInteractionSurface(
          onOpenThread: onOpenThread,
          emojiRepositoryFactory: repository == null ? null : () => repository,
          accountId: repository == null ? '' : 'account-a',
          onToggleReaction: onToggleReaction,
          child: const SizedBox(height: 100, child: Text('Message')),
        ),
      ),
    ),
  ),
);

Color _expectedHighlightColor(WidgetTester tester) {
  final BuildContext context = tester.element(
    find.byKey(const ValueKey<String>('message-highlight')),
  );
  return Theme.of(context).colorScheme.primary.withValues(alpha: 0.10);
}
