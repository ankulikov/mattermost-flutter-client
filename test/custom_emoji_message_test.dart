import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

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

  testWidgets('renders a cached custom emoji in a tappable reaction', (
    WidgetTester tester,
  ) async {
    final CustomEmojiContent content = CustomEmojiContent(
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
      contentType: 'image/png',
    );
    PostReaction? toggled;
    final ChannelPost post = ChannelPost(
      id: 'post-1',
      channelId: 'channel-1',
      author: const PostAuthor(id: 'ada', displayName: 'Ada'),
      sentAt: DateTime.fromMillisecondsSinceEpoch(1),
      message: 'Hello',
      customEmojis: const <CustomEmojiReference>[reference],
      reactions: const <PostReaction>[
        PostReaction(
          emoji: ':party_parrot:',
          emojiName: 'party_parrot',
          count: 2,
        ),
        PostReaction(emoji: '👍', emojiName: 'thumbsup', count: 3),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customEmojiProvider(
            reference,
          ).overrideWithValue(AsyncValue<CustomEmojiContent>.data(content)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MessageReactions(
              post: post,
              semanticsLabel: 'Reactions',
              onToggle: (PostReaction reaction) async => toggled = reaction,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    final Finder customIcon = find.byKey(
      const ValueKey<String>('reaction-icon-party_parrot'),
    );
    final Finder builtInIcon = find.byKey(
      const ValueKey<String>('reaction-icon-thumbsup'),
    );
    expect(tester.getSize(customIcon), const Size.square(20));
    expect(tester.getSize(builtInIcon), const Size.square(20));
    final Finder customChip = find.byKey(
      const ValueKey<String>('reaction-chip-party_parrot'),
    );
    final Finder builtInChip = find.byKey(
      const ValueKey<String>('reaction-chip-thumbsup'),
    );
    expect(tester.getSize(customChip).height, lessThan(44));
    expect(
      tester.getSize(customChip).height,
      tester.getSize(builtInChip).height,
    );
    final BoxDecoration decoration =
        tester.widget<DecoratedBox>(customChip).decoration as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(6));
    await tester.tap(
      find.byKey(const ValueKey<String>('reaction-party_parrot')),
    );
    await tester.pump();
    expect(toggled?.emojiName, 'party_parrot');
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
