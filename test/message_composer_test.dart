import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/ui/messages/message_composer_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_composer.dart';

void main() {
  testWidgets('keeps a failed draft and reuses its pending post id', (
    WidgetTester tester,
  ) async {
    final List<String> pendingIds = <String>[];
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageComposer(
            destinationId: 'channel-1',
            placeholder: 'Message channel',
            onSubmit: (String message, String pendingPostId) async {
              pendingIds.add(pendingPostId);
              attempts += 1;
              if (attempts == 1) throw StateError('offline');
            },
          ),
        ),
      ),
    );

    final Finder input = find.byKey(
      const ValueKey<String>('message-input-channel-1'),
    );
    final Finder send = find.byKey(
      const ValueKey<String>('send-message-channel-1'),
    );
    await tester.enterText(input, 'Keep this draft');
    await tester.pump();
    await tester.tap(send);
    await tester.pump();

    expect(find.text('Keep this draft'), findsOneWidget);
    expect(find.text(MessageComposerStrings.sendFailed), findsOneWidget);

    await tester.tap(send);
    await tester.pump();

    expect(pendingIds, hasLength(2));
    expect(pendingIds[1], pendingIds[0]);
    expect(find.text('Keep this draft'), findsNothing);
    expect(find.text(MessageComposerStrings.sendFailed), findsNothing);
  });

  testWidgets(
    'Enter sends, Shift+Enter adds a line, and send is single-flight',
    (WidgetTester tester) async {
      final Completer<void> completion = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageComposer(
              destinationId: 'channel-1',
              placeholder: 'Message channel',
              onSubmit: (String message, String pendingPostId) {
                calls += 1;
                return completion.future;
              },
            ),
          ),
        ),
      );

      final Finder input = find.byKey(
        const ValueKey<String>('message-input-channel-1'),
      );
      await tester.enterText(input, 'Send with Enter');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(calls, 0);
      expect(
        tester.widget<TextField>(input).controller?.text,
        'Send with Enter\n',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(calls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completion.complete();
      await tester.pump();
      expect(find.text('Send with Enter'), findsNothing);
    },
  );

  testWidgets('lays out at compact width with large text', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: MessageComposer(
              destinationId: 'compact',
              placeholder: 'Write a message',
              onSubmit: (String message, String pendingPostId) async {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
