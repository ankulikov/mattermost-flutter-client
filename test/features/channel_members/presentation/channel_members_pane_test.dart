import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/channel_members/domain/channel_member.dart';
import 'package:mattermost_flutter/src/features/channel_members/domain/channel_members_repository.dart';
import 'package:mattermost_flutter/src/features/channel_members/presentation/channel_member_count_button.dart';
import 'package:mattermost_flutter/src/features/channel_members/presentation/channel_members_pane.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';
import 'package:mattermost_flutter/src/ui/users/widgets/user_avatar_image.dart';
import 'package:mattermost_flutter/src/ui/users/widgets/user_profile_card.dart';

void main() {
  testWidgets('shows compact member rows without usernames', (
    WidgetTester tester,
  ) async {
    final _ChannelMembersRepository repository = _ChannelMembersRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          channelMembersRepositoryProvider.overrideWithValue(repository),
          userAvatarProvider.overrideWith((ref, request) async => null),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SizedBox(
                width: 380,
                child: ChannelMembersPane(channel: _channel, onClose: _noop),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 members'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('@ada'), findsNothing);
    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.byTooltip('Channel admin'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('user-avatar-fallback-ada')),
      findsOneWidget,
    );
    final Finder adaTile = find.byKey(
      const ValueKey<String>('channel-member-ada'),
    );
    expect(tester.widget<ListTile>(adaTile).dense, isTrue);
    expect(
      tester.widget<ListTile>(adaTile).visualDensity,
      const VisualDensity(vertical: -2),
    );
    expect(
      tester
          .widget<UserAvatarImage>(
            find.descendant(
              of: adaTile,
              matching: find.byType(UserAvatarImage),
            ),
          )
          .radius,
      12,
    );
    expect(
      tester.widget<Text>(find.text('Ada Lovelace')).style,
      Theme.of(tester.element(adaTile)).textTheme.bodyMedium,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens the shared user profile card when a member is tapped', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          channelMembersRepositoryProvider.overrideWithValue(
            _ChannelMembersRepository(),
          ),
          userProfileProvider.overrideWith(
            (Ref ref, String userId) async => const UserProfile(
              id: 'ada',
              firstName: 'Ada',
              lastName: 'Lovelace',
              username: 'ada',
              nickname: '',
              position: 'Mathematician',
              email: 'ada@example.com',
              presence: UserPresence.online,
            ),
          ),
          userAvatarProvider.overrideWith((ref, request) async => null),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ChannelMembersPane(channel: _channel, onClose: _noop),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('channel-member-ada')));
    await tester.pumpAndSettle();

    expect(find.byType(UserProfileCard), findsOneWidget);
    expect(find.text('Mathematician'), findsOneWidget);
  });

  testWidgets('shows an initial error and retries without closing the pane', (
    WidgetTester tester,
  ) async {
    final _ChannelMembersRepository repository = _ChannelMembersRepository(
      failFirstPageOnce: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          channelMembersRepositoryProvider.overrideWithValue(repository),
          userAvatarProvider.overrideWith((ref, request) async => null),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ChannelMembersPane(channel: _channel, onClose: _noop),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load channel members'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('channel-members-pane-channel-1')),
      findsOneWidget,
    );
  });

  testWidgets('member count button opens the member workflow', (
    WidgetTester tester,
  ) async {
    var pressed = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          channelMembersRepositoryProvider.overrideWithValue(
            _ChannelMembersRepository(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChannelMemberCountButton(
              channelId: _channel.id,
              onPressed: () => pressed = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('channel-member-count-channel-1')),
    );
    expect(pressed, isTrue);
  });
}

const SidebarChannel _channel = SidebarChannel(
  id: 'channel-1',
  teamId: 'team-1',
  name: 'town-square',
  displayName: 'Town Square',
  kind: ChannelKind.publicChannel,
);

void _noop() {}

final class _ChannelMembersRepository implements ChannelMembersRepository {
  _ChannelMembersRepository({this.failFirstPageOnce = false});

  final bool failFirstPageOnce;
  var _firstPageCalls = 0;

  @override
  Future<int> getCount(String channelId) async => 2;

  @override
  Future<ChannelMembersPage> loadPage({
    required String channelId,
    required int page,
    required int perPage,
  }) async {
    if (page == 0 && failFirstPageOnce && _firstPageCalls++ == 0) {
      throw StateError('offline');
    }
    return ChannelMembersPage(
      members: <ChannelMember>[
        ChannelMember(
          user: _user('ada', 'Ada', 'Lovelace'),
          isChannelAdmin: true,
        ),
        ChannelMember(user: _user('grace', 'Grace', 'Hopper')),
      ],
    );
  }
}

UserSummary _user(String id, String firstName, String lastName) => UserSummary(
  id: id,
  firstName: firstName,
  lastName: lastName,
  username: id,
  nickname: '',
  position: '',
  email: '$id@example.com',
  profileImageUpdatedAt: 10,
);
