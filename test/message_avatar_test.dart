import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/user_avatar.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  const PostAuthor author = PostAuthor(
    id: 'ada',
    displayName: 'Ada Lovelace',
    profileImageUpdatedAt: 42,
  );

  testWidgets('shows initials while loading and replaces them with the image', (
    WidgetTester tester,
  ) async {
    final providerCompleter = Completer<UserAvatar?>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userAvatarProvider.overrideWith(
            (Ref ref, UserAvatarRequest input) => providerCompleter.future,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: MessageAvatar(author: author)),
        ),
      ),
    );

    expect(find.text('AL'), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    providerCompleter.complete(
      UserAvatar(bytes: _onePixelPng, contentType: 'image/png'),
    );
    await tester.pump();

    expect(find.text('AL'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('keeps initials when loading fails', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userAvatarProvider.overrideWith(
            (Ref ref, UserAvatarRequest input) =>
                Future<UserAvatar?>.error(StateError('not found')),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: MessageAvatar(author: author)),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('AL'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '/x8AAusB9Y9Z4VAAAAAASUVORK5CYII=',
);
