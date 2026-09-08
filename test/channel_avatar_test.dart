import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/user_avatar.dart';
import 'package:mattermost_flutter/src/ui/channels/widgets/channel_avatar.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  const SidebarChannel channel = SidebarChannel(
    id: 'dm-1',
    teamId: '',
    name: 'me__ada',
    displayName: 'Ada Lovelace',
    kind: ChannelKind.directMessage,
    profileImage: SidebarProfileImage(userId: 'ada', updatedAt: 42),
  );

  testWidgets('shows DM initials immediately then replaces them with avatar', (
    WidgetTester tester,
  ) async {
    final Completer<UserAvatar?> avatarCompleter = Completer<UserAvatar?>();
    UserAvatarRequest? requestedAvatar;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userAvatarProvider.overrideWith((Ref ref, UserAvatarRequest request) {
            requestedAvatar = request;
            return avatarCompleter.future;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChannelAvatar(channel: channel)),
        ),
      ),
    );

    expect(requestedAvatar, (userId: 'ada', profileImageUpdatedAt: 42));
    expect(find.text('AL'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('user-avatar-image-ada')),
      findsNothing,
    );

    avatarCompleter.complete(
      UserAvatar(bytes: _onePixelPng, contentType: 'image/png'),
    );
    await tester.pump();

    expect(find.text('AL'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('user-avatar-image-ada')),
      findsOneWidget,
    );
  });

  testWidgets('keeps the DM initials when avatar loading fails', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userAvatarProvider.overrideWith(
            (Ref ref, UserAvatarRequest request) =>
                Future<UserAvatar?>.error(StateError('offline')),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChannelAvatar(channel: channel)),
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
