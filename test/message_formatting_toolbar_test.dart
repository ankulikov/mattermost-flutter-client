import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/ui/messages/message_composer_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_formatting_toolbar.dart';

void main() {
  testWidgets('shows every control in reference order on expanded widths', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const _ToolbarApp());

    expect(_visibleControlKeys(tester), <Key>[
      const ValueKey<String>('message-formatting-bold'),
      const ValueKey<String>('message-formatting-italic'),
      const ValueKey<String>('message-formatting-strike'),
      const ValueKey<String>('message-formatting-heading'),
      const ValueKey<String>('message-formatting-code'),
      const ValueKey<String>('message-formatting-quote'),
      const ValueKey<String>('message-formatting-bulletedList'),
      const ValueKey<String>('message-formatting-orderedList'),
    ]);
    expect(
      find.byKey(const ValueKey<String>('message-formatting-overflow')),
      findsNothing,
    );
  });

  testWidgets('keeps common controls and moves block commands to overflow', (
    WidgetTester tester,
  ) async {
    MessageFormattingCommand? selected;
    await tester.binding.setSurfaceSize(const Size(699, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _ToolbarApp(
        onCommandSelected: (MessageFormattingCommand command) {
          selected = command;
        },
      ),
    );

    expect(_visibleControlKeys(tester), <Key>[
      const ValueKey<String>('message-formatting-bold'),
      const ValueKey<String>('message-formatting-italic'),
      const ValueKey<String>('message-formatting-strike'),
      const ValueKey<String>('message-formatting-heading'),
      const ValueKey<String>('message-formatting-overflow'),
    ]);
    expect(
      find.byKey(const ValueKey<String>('message-formatting-code')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('message-formatting-overflow')),
    );
    await tester.pumpAndSettle();

    expect(find.text(MessageComposerStrings.formatCode), findsOneWidget);
    expect(find.text(MessageComposerStrings.formatQuote), findsOneWidget);
    expect(
      find.text(MessageComposerStrings.formatBulletedList),
      findsOneWidget,
    );
    expect(find.text(MessageComposerStrings.formatOrderedList), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('message-formatting-menu-quote')),
    );
    await tester.pumpAndSettle();

    expect(selected, MessageFormattingCommand.quote);
  });

  testWidgets('show-all mode wraps instead of hiding compact controls', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const _ToolbarApp(showAllCommands: true));

    for (final MessageFormattingCommand command
        in MessageFormattingCommand.values) {
      expect(
        find.byKey(ValueKey<String>('message-formatting-${command.name}')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey<String>('message-formatting-overflow')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports the label and active toggle state to semantics', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const _ToolbarApp(
        activeCommands: <MessageFormattingCommand>{
          MessageFormattingCommand.bold,
        },
      ),
    );

    final SemanticsNode bold = tester.getSemantics(
      find.byKey(const ValueKey<String>('message-formatting-bold')),
    );
    final SemanticsNode italic = tester.getSemantics(
      find.byKey(const ValueKey<String>('message-formatting-italic')),
    );

    expect(bold.label, MessageComposerStrings.formatBold);
    expect(bold.flagsCollection.isButton, isTrue);
    expect(bold.flagsCollection.isToggled, Tristate.isTrue);
    expect(italic.label, MessageComposerStrings.formatItalic);
    expect(italic.flagsCollection.isToggled, Tristate.isFalse);
    semantics.dispose();
  });

  testWidgets('preserves the editor focus and selection after a command tap', (
    WidgetTester tester,
  ) async {
    final FocusNode editorFocusNode = FocusNode();
    final TextEditingController controller = TextEditingController.fromValue(
      const TextEditingValue(
        text: 'selection',
        selection: TextSelection(baseOffset: 1, extentOffset: 6),
      ),
    );
    addTearDown(editorFocusNode.dispose);
    addTearDown(controller.dispose);
    MessageFormattingCommand? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(controller: controller, focusNode: editorFocusNode),
              MessageFormattingToolbar(
                activeCommands: const <MessageFormattingCommand>{},
                editorFocusNode: editorFocusNode,
                onCommandSelected: (MessageFormattingCommand command) {
                  selected = command;
                },
              ),
            ],
          ),
        ),
      ),
    );
    editorFocusNode.requestFocus();
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('message-formatting-bold')),
    );
    await tester.pump();

    expect(selected, MessageFormattingCommand.bold);
    expect(editorFocusNode.hasFocus, isTrue);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 1, extentOffset: 6),
    );
  });

  testWidgets('does not overflow at compact width with large text', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: _ToolbarApp()),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}

List<Key> _visibleControlKeys(WidgetTester tester) => tester
    .widgetList<Semantics>(find.byType(Semantics))
    .map((Semantics semantics) => semantics.key)
    .whereType<Key>()
    .toList(growable: false);

class _ToolbarApp extends StatelessWidget {
  const _ToolbarApp({
    this.activeCommands = const <MessageFormattingCommand>{},
    this.onCommandSelected,
    this.showAllCommands = false,
  });

  final Set<MessageFormattingCommand> activeCommands;
  final ValueChanged<MessageFormattingCommand>? onCommandSelected;
  final bool showAllCommands;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: MessageFormattingToolbar(
        activeCommands: activeCommands,
        showAllCommands: showAllCommands,
        onCommandSelected: onCommandSelected ?? (_) {},
      ),
    ),
  );
}
