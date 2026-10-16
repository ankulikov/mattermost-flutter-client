import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/repositories/channel_repository.dart';
import 'package:mattermost_flutter/src/ui/channels/channel_sidebar_controller.dart';
import 'package:mattermost_flutter/src/ui/channels/selected_channel_controller.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  final AuthSession session = AuthSession(
    serverUrl: Uri.parse('https://chat.example.com'),
    userId: 'me',
    username: 'current',
  );

  test('buffers realtime posts while the initial snapshot loads', () async {
    final Completer<ChannelSidebarSnapshot> initial =
        Completer<ChannelSidebarSnapshot>();
    final _RealtimeChannelRepository repository = _RealtimeChannelRepository(
      initialLoad: initial.future,
    );
    final ProviderContainer container = _container(session, repository);
    addTearDown(() async {
      container.dispose();
      await repository.dispose();
    });

    final Future<ChannelSidebarViewState> loading = container.read(
      channelSidebarProvider.future,
    );
    await _flush();
    expect(repository.watchCalls, 1);
    repository.add(
      const ChannelSidebarMessagePosted(
        channelId: 'channel-1',
        isThreadReply: false,
      ),
    );
    initial.complete(_snapshot());

    expect(_channel((await loading).snapshot, 'channel-1').isUnread, isTrue);
  });

  test('applies read events and views a selected channel', () async {
    final _RealtimeChannelRepository repository = _RealtimeChannelRepository();
    final ProviderContainer container = _container(session, repository);
    addTearDown(() async {
      container.dispose();
      await repository.dispose();
    });

    await container.read(channelSidebarProvider.future);
    repository.add(
      const ChannelSidebarUnreadChanged(channelId: 'channel-1', isUnread: true),
    );
    await _flush();
    expect(_currentChannel(container, 'channel-1').isUnread, isTrue);

    container
        .read(selectedChannelProvider.notifier)
        .select(_currentChannel(container, 'channel-1'));
    await _flush();

    expect(repository.viewedChannelIds, <String>['channel-1']);
    expect(_currentChannel(container, 'channel-1').isUnread, isFalse);
  });

  test('reloads authoritatively after realtime recovery', () async {
    final _RealtimeChannelRepository repository = _RealtimeChannelRepository();
    final ProviderContainer container = _container(session, repository);
    addTearDown(() async {
      container.dispose();
      await repository.dispose();
    });

    await container.read(channelSidebarProvider.future);
    repository.unreadOnLoad = true;
    repository.add(const ChannelSidebarRefreshRequired());
    await _flush();

    expect(repository.loadCalls, 2);
    expect(_currentChannel(container, 'channel-1').isUnread, isTrue);
  });
}

ProviderContainer _container(
  AuthSession session,
  ChannelRepository repository,
) => ProviderContainer(
  overrides: [
    authSessionProvider.overrideWithValue(session),
    channelRepositoryProvider.overrideWithValue(repository),
  ],
);

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

SidebarChannel _currentChannel(ProviderContainer container, String channelId) =>
    _channel(
      container.read(channelSidebarProvider).requireValue.snapshot,
      channelId,
    );

SidebarChannel _channel(ChannelSidebarSnapshot snapshot, String channelId) =>
    snapshot.sections
        .expand((SidebarSection section) => section.channels)
        .singleWhere((SidebarChannel channel) => channel.id == channelId);

ChannelSidebarSnapshot _snapshot({bool isUnread = false}) =>
    ChannelSidebarSnapshot(
      team: const SidebarTeam(id: 'team-1', displayName: 'Team'),
      sections: <SidebarSection>[
        SidebarSection(
          id: 'channels',
          displayName: 'Channels',
          channels: <SidebarChannel>[
            SidebarChannel(
              id: 'channel-1',
              teamId: 'team-1',
              name: 'channel-1',
              displayName: 'Channel one',
              kind: ChannelKind.publicChannel,
              isUnread: isUnread,
            ),
          ],
        ),
      ],
    );

final class _RealtimeChannelRepository
    implements ChannelRepository, ChannelSidebarRealtimeRepository {
  _RealtimeChannelRepository({this.initialLoad});

  final Future<ChannelSidebarSnapshot>? initialLoad;
  final StreamController<ChannelSidebarRealtimeEvent> _events =
      StreamController<ChannelSidebarRealtimeEvent>.broadcast(sync: true);
  final List<String> viewedChannelIds = <String>[];
  var loadCalls = 0;
  var watchCalls = 0;
  var unreadOnLoad = false;

  @override
  Future<ChannelSidebarSnapshot> load(AuthSession session) async {
    loadCalls += 1;
    if (loadCalls == 1 && initialLoad != null) return initialLoad!;
    return _snapshot(isUnread: unreadOnLoad);
  }

  @override
  Stream<ChannelSidebarRealtimeEvent> watchSidebar({
    required AuthSession session,
  }) {
    watchCalls += 1;
    return _events.stream;
  }

  @override
  Future<void> markChannelViewed({
    required AuthSession session,
    required String channelId,
    String? previousChannelId,
  }) async {
    viewedChannelIds.add(channelId);
  }

  @override
  Future<SidebarChannel> openDirectMessage({
    required String currentUserId,
    required String otherUserId,
    required String otherUserDisplayName,
  }) => throw UnimplementedError();

  void add(ChannelSidebarRealtimeEvent event) => _events.add(event);

  Future<void> dispose() => _events.close();
}
