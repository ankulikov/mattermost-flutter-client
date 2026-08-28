import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/app/di/app_providers.dart';
import 'package:mattermost_flutter/src/features/emojis/domain/custom_emoji.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message.dart';
import 'package:mattermost_flutter/src/features/messages/presentation/message_primitives.dart';

void main() {
  const CustomEmojiReference reference = CustomEmojiReference(
    name: 'party_parrot',
    id: 'emoji-1',
    updatedAt: 42,
  );

  testWidgets('renders custom emoji bytes at the scaled text size', (
    WidgetTester tester,
  ) async {
    final CustomEmojiContent content = CustomEmojiContent(
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
      contentType: 'image/png',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customEmojiProvider(
            reference,
          ).overrideWithValue(AsyncValue<CustomEmojiContent>.data(content)),
        ],
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MaterialApp(home: Scaffold(body: _message(reference))),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    final SizedBox box = tester.widget<SizedBox>(
      find.ancestor(of: find.byType(Image), matching: find.byType(SizedBox)),
    );
    expect(box.width, 28);
    expect(box.height, 28);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the shortcode during loading and after failure', (
    WidgetTester tester,
  ) async {
    Future<void> pumpWith(AsyncValue<CustomEmojiContent> value) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [
              customEmojiProvider(reference).overrideWithValue(value),
            ],
            child: MaterialApp(home: Scaffold(body: _message(reference))),
          ),
        );

    await pumpWith(const AsyncValue<CustomEmojiContent>.loading());
    expect(find.text(':party_parrot:'), findsOneWidget);

    await pumpWith(
      AsyncValue<CustomEmojiContent>.error(
        StateError('unavailable'),
        StackTrace.empty,
      ),
    );
    expect(find.text(':party_parrot:'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}

Widget _message(CustomEmojiReference reference) => MessageBody(
  post: ChannelPost(
    id: 'post-1',
    channelId: 'channel-1',
    author: const PostAuthor(id: 'ada', displayName: 'Ada'),
    sentAt: DateTime.fromMillisecondsSinceEpoch(1),
    message: ':party_parrot:',
    customEmojis: <CustomEmojiReference>[reference],
  ),
);
