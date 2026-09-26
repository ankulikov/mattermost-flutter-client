import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/repositories/emoji_repository.dart';
import 'package:mattermost_flutter/src/ui/messages/mattermost_markdown.dart';
import 'package:mattermost_flutter/src/ui/messages/message_actions_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_interaction_surface.dart';

import 'support/fake_emoji_repository.dart';

void main() {
  testWidgets('touch tap on Markdown text opens its thread exactly once', (
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
    expect(decoration.color, Colors.transparent);
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
    await tester.pump();

    final Container highlight = tester.widget(
      find.byKey(const ValueKey<String>('message-highlight')),
    );
    final BoxDecoration decoration = highlight.decoration! as BoxDecoration;
    expect(decoration.color, _expectedHighlightColor(tester));
    final List<MethodCall> hapticCalls = platformCalls
        .where((MethodCall call) => call.method == 'HapticFeedback.vibrate')
        .toList(growable: false);
    expect(hapticCalls, hasLength(1));
    expect(hapticCalls.single.arguments, 'HapticFeedbackType.lightImpact');

    await touch.up();
    await tester.pumpAndSettle();

    expect(openCount, 0);
    expect(
      find.byKey(const ValueKey<String>('message-actions-bottom-sheet')),
      findsOneWidget,
    );
    expect(find.text(MessageActionsStrings.followThread), findsOneWidget);
    await _dismissActionsSheet(tester);
  });

  testWidgets('copies the post permalink from the touch actions sheet', (
    WidgetTester tester,
  ) async {
    MethodCall? clipboardCall;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') clipboardCall = call;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      _app(
        onOpenThread: () {},
        postPermalink: Uri.parse('https://chat.example.com/team-a/pl/post-1'),
      ),
    );

    await tester.longPress(find.text('Message'), kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();
    await tester.tap(find.text(MessageActionsStrings.copyLink));
    await tester.pumpAndSettle();

    expect(clipboardCall?.method, 'Clipboard.setData');
    expect(clipboardCall?.arguments, <String, Object>{
      'text': 'https://chat.example.com/team-a/pl/post-1',
    });
    expect(find.text(MessageActionsStrings.linkCopied), findsOneWidget);
  });

  testWidgets('runs deletion from the touch message actions', (
    WidgetTester tester,
  ) async {
    var deleted = 0;
    await tester.pumpWidget(
      _app(
        onOpenThread: () {},
        onDelete: () async {
          deleted += 1;
          return true;
        },
        canDelete: true,
        canEdit: true,
      ),
    );

    await tester.longPress(find.text('Message'), kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(MessageActionsStrings.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text(MessageActionsStrings.delete));
    await tester.pumpAndSettle();

    expect(deleted, 1);
  });

  testWidgets('touch tap on message padding opens its thread exactly once', (
    WidgetTester tester,
  ) async {
    var openCount = 0;
    await tester.pumpWidget(_app(onOpenThread: () => openCount += 1));

    final Rect surface = tester.getRect(
      find.byKey(const ValueKey<String>('message-highlight')),
    );
    await tester.tapAt(
      Offset(surface.left + 2, surface.bottom - 2),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();

    expect(openCount, 1);
  });

  testWidgets('does not show Edit or Delete for another author post', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(onOpenThread: () {}));

    await tester.longPress(find.text('Message'), kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();

    expect(find.text(MessageActionsStrings.delete), findsNothing);
    expect(find.text(MessageActionsStrings.edit), findsNothing);
  });

  testWidgets(
    'touch long press on Markdown text opens one sheet, not a thread',
    (WidgetTester tester) async {
      var openCount = 0;
      await tester.pumpWidget(_app(onOpenThread: () => openCount += 1));

      await tester.longPress(
        find.text('Message'),
        kind: PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();

      expect(openCount, 0);
      expect(
        find.byKey(const ValueKey<String>('message-actions-bottom-sheet')),
        findsOneWidget,
      );
      await _dismissActionsSheet(tester);
    },
  );

  testWidgets('touch long press on message padding opens one sheet', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(onOpenThread: () {}));
    final Rect surface = tester.getRect(
      find.byKey(const ValueKey<String>('message-highlight')),
    );

    final TestGesture touch = await tester.startGesture(
      Offset(surface.left + 2, surface.bottom - 2),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 600));
    await touch.up();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('message-actions-bottom-sheet')),
      findsOneWidget,
    );
    await _dismissActionsSheet(tester);
  });

  testWidgets('touch double tap and drag on Markdown text do not select it', (
    WidgetTester tester,
  ) async {
    var openCount = 0;
    await tester.pumpWidget(_app(onOpenThread: () => openCount += 1));

    await tester.tap(find.text('Message'), kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.text('Message'), kind: PointerDeviceKind.touch);
    await tester.pump();

    final TestGesture drag = await tester.startGesture(
      tester.getCenter(find.text('Message')),
      kind: PointerDeviceKind.touch,
    );
    await drag.moveBy(const Offset(48, 0));
    await drag.up();
    await tester.pump();

    expect(openCount, 2);
    expect(_selectionOverlay(tester), isNull);
    expect(
      find.byKey(const ValueKey<String>('message-actions-bottom-sheet')),
      findsNothing,
    );
  });

  testWidgets('thread Markdown blocks touch selection without a tap action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(onOpenThread: null));

    await tester.tap(find.text('Message'), kind: PointerDeviceKind.touch);
    await tester.pump();
    expect(_selectionOverlay(tester), isNull);

    await tester.longPress(find.text('Message'), kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('message-actions-bottom-sheet')),
      findsOneWidget,
    );
    await _dismissActionsSheet(tester);
  });

  testWidgets('thread touch mode opens actions on tap', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        onOpenThread: null,
        touchBehavior: MessageTouchBehavior.actionsOnTap,
      ),
    );

    await tester.tap(find.text('Message'), kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('message-actions-bottom-sheet')),
      findsOneWidget,
    );
    await _dismissActionsSheet(tester);
  });

  testWidgets('thread touch actions fit compact width with large text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        onOpenThread: null,
        width: 300,
        textScaler: const TextScaler.linear(2),
        touchBehavior: MessageTouchBehavior.actionsOnTap,
      ),
    );

    await tester.tap(find.text('Message'), kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('message-actions-bottom-sheet')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await _dismissActionsSheet(tester);
  });

  testWidgets('thread long press selects text and puts Quote first', (
    WidgetTester tester,
  ) async {
    String? quoted;
    await tester.pumpWidget(
      _app(
        onOpenThread: null,
        touchBehavior: MessageTouchBehavior.actionsOnTap,
        onQuoteSelection: (String text) => quoted = text,
      ),
    );

    await tester.longPress(find.text('Message'), kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();

    expect(_selectionOverlay(tester), isNotNull);
    expect(
      find.byKey(const ValueKey<String>('message-actions-bottom-sheet')),
      findsNothing,
    );
    final Finder quote = find.text(MessageActionsStrings.quote);
    final Finder copy = find.text('Copy');
    expect(quote, findsOneWidget);
    expect(copy, findsOneWidget);
    expect(tester.getTopLeft(quote).dx, lessThan(tester.getTopLeft(copy).dx));

    await tester.tap(quote);
    await tester.pumpAndSettle();

    expect(quoted, 'Message');
  });

  testWidgets('stylus tap uses the Markdown touch interaction', (
    WidgetTester tester,
  ) async {
    var openCount = 0;
    await tester.pumpWidget(_app(onOpenThread: () => openCount += 1));

    await tester.tap(find.text('Message'), kind: PointerDeviceKind.stylus);
    await tester.pump();
    expect(openCount, 1);
  });

  testWidgets('inverted stylus long press opens message actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(onOpenThread: () {}));

    final Rect markdown = tester.getRect(find.text('Message'));
    await tester.longPressAt(
      Offset(markdown.left + 4, markdown.center.dy),
      kind: PointerDeviceKind.invertedStylus,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('message-actions-bottom-sheet')),
      findsOneWidget,
    );
    await _dismissActionsSheet(tester);
  });

  testWidgets(
    'mouse click keeps Markdown selection behavior and hover actions',
    (WidgetTester tester) async {
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
      expect(openCount, 0);
    },
  );

  testWidgets('mouse click on message padding opens its thread exactly once', (
    WidgetTester tester,
  ) async {
    var openCount = 0;
    await tester.pumpWidget(_app(onOpenThread: () => openCount += 1));
    final Rect surface = tester.getRect(
      find.byKey(const ValueKey<String>('message-highlight')),
    );

    await tester.tapAt(
      Offset(surface.left + 2, surface.bottom - 2),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(openCount, 1);
    expect(
      find.byKey(const ValueKey<String>('message-actions-bottom-sheet')),
      findsNothing,
    );
  });

  testWidgets('quick actions stay interactive above the following message', (
    WidgetTester tester,
  ) async {
    var openCount = 0;
    await tester.pumpWidget(
      _app(
        onOpenThread: () => openCount += 1,
        messageHeight: 24,
        followingMessage: true,
        canDelete: true,
        canEdit: true,
      ),
    );
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);

    await mouse.addPointer(location: tester.getCenter(find.text('Message')));
    await tester.pumpAndSettle();

    final Finder actions = find.byKey(
      const ValueKey<String>('quick-message-actions'),
    );
    expect(actions, findsOneWidget);
    expect(
      tester.getBottomRight(actions).dy,
      greaterThan(tester.getBottomRight(find.text('Message')).dy),
    );

    final Rect moreButton = tester.getRect(
      find.byKey(const ValueKey<String>('more-message-actions')),
    );
    final Offset actionPoint = Offset(
      moreButton.center.dx,
      moreButton.bottom - 2,
    );
    await mouse.moveTo(actionPoint);
    await tester.pumpAndSettle();
    expect(actions, findsOneWidget);

    await mouse.down(actionPoint);
    await mouse.up();
    await tester.pumpAndSettle();

    expect(openCount, 0);
    expect(find.text(MessageActionsStrings.forward), findsOneWidget);
    expect(find.text(MessageActionsStrings.delete), findsOneWidget);
    expect(find.text(MessageActionsStrings.edit), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mouse popup keeps actions open and copies the post permalink', (
    WidgetTester tester,
  ) async {
    MethodCall? clipboardCall;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') clipboardCall = call;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      _app(
        onOpenThread: () {},
        postPermalink: Uri.parse('https://chat.example.com/team-a/pl/post-1'),
      ),
    );
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.text('Message')));
    await tester.pumpAndSettle();

    await mouse.down(
      tester.getCenter(
        find.byKey(const ValueKey<String>('more-message-actions')),
      ),
    );
    await mouse.up();
    await tester.pumpAndSettle();

    final Finder copyLink = find.text(MessageActionsStrings.copyLink);
    await mouse.moveTo(tester.getCenter(copyLink));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('quick-message-actions')),
      findsOneWidget,
    );
    await mouse.down(tester.getCenter(copyLink));
    await mouse.up();
    await tester.pumpAndSettle();

    expect(clipboardCall?.arguments, <String, Object>{
      'text': 'https://chat.example.com/team-a/pl/post-1',
    });
    expect(find.text(MessageActionsStrings.linkCopied), findsOneWidget);
  });

  testWidgets('mouse popup hides owner-only actions for another author', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(onOpenThread: () {}));
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.text('Message')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('more-message-actions')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(find.text(MessageActionsStrings.edit), findsNothing);
    expect(find.text(MessageActionsStrings.delete), findsNothing);
  });

  testWidgets('mouse long press on Markdown text does not open touch sheet', (
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
  required VoidCallback? onOpenThread,
  double width = 600,
  double messageHeight = 100,
  bool followingMessage = false,
  TextScaler textScaler = TextScaler.noScaling,
  CustomEmojiRepository? repository,
  Future<bool> Function(String emojiName)? onToggleReaction,
  Future<bool> Function()? onDelete,
  bool canDelete = false,
  bool canEdit = false,
  Uri? postPermalink,
  MessageTouchBehavior touchBehavior = MessageTouchBehavior.openThreadOnTap,
  ValueChanged<String>? onQuoteSelection,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            MessageInteractionSurface(
              onOpenThread: onOpenThread,
              emojiRepositoryFactory: repository == null
                  ? null
                  : () => repository,
              accountId: repository == null ? '' : 'account-a',
              onToggleReaction: onToggleReaction,
              onDelete: onDelete,
              canDelete: canDelete,
              canEdit: canEdit,
              postPermalink: postPermalink,
              touchBehavior: touchBehavior,
              child: SizedBox(
                height: messageHeight,
                child: MattermostMarkdown(
                  data: 'Message',
                  onQuoteSelection: onQuoteSelection,
                ),
              ),
            ),
            if (followingMessage)
              const SizedBox(
                height: 48,
                width: double.infinity,
                child: ColoredBox(
                  color: Colors.white,
                  child: Text('Following message'),
                ),
              ),
          ],
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

SelectionOverlay? _selectionOverlay(WidgetTester tester) => tester
    .state<SelectionAreaState>(find.byType(SelectionArea))
    .selectableRegion
    .selectionOverlay;

Future<void> _dismissActionsSheet(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator)).pop();
  await tester.pumpAndSettle();
}
