import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
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

  testWidgets('shows direct-user presence at compact and expanded widths', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final double width in <double>[390, 1200]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userAvatarProvider.overrideWith(
              (Ref ref, UserAvatarRequest request) async => null,
            ),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: ChannelAvatar(
                  channel: channel.copyWith(presence: UserPresence.away),
                  size: 16,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byTooltip('Away'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('channel-presence-dm-1')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Away'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'labels an unavailable direct-user status without claiming offline',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChannelAvatar(
              channel: SidebarChannel(
                id: 'dm-unknown',
                teamId: '',
                name: 'me__unknown',
                displayName: 'Unknown',
                kind: ChannelKind.directMessage,
              ),
            ),
          ),
        ),
      );

      expect(find.byTooltip('Status unavailable'), findsOneWidget);
      expect(find.bySemanticsLabel('Status unavailable'), findsOneWidget);
    },
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
