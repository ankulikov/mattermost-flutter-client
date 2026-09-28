import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_page_controller.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  test(
    'disposing page state resets tabs, scroll and focus without stopping session realtime projection',
    () async {
      final StreamController<InboxRealtimeEvent> realtime =
          StreamController<InboxRealtimeEvent>();
      addTearDown(realtime.close);
      final ProviderContainer container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWithValue(_session),
          inboxRepositoryProvider.overrideWithValue(
            _InboxRepository(realtime.stream),
          ),
          postponedRepositoryProvider.overrideWithValue(
            const _PostponedRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(inboxSessionProvider.future);
      await Future<void>.delayed(Duration.zero);

      final ProviderSubscription<InboxPageViewState> pageSubscription =
          container.listen(inboxPageProvider, (_, _) {});
      final InboxPageController pageController = container.read(
        inboxPageProvider.notifier,
      );
      pageController
        ..selectTab(InboxPageTab.postponed)
        ..saveScrollOffset(InboxPageTab.postponed, 48)
        ..focusItem('post:focused');
      expect(
        container.read(inboxPageProvider),
        isA<InboxPageViewState>()
            .having(
              (InboxPageViewState state) => state.selectedTab,
              'selected tab',
              InboxPageTab.postponed,
            )
            .having(
              (InboxPageViewState state) => state.postponedScrollOffset,
              'postponed scroll offset',
              48,
            )
            .having(
              (InboxPageViewState state) => state.focusedItemKey,
              'focused item',
              'post:focused',
            ),
      );

      pageSubscription.close();
      await Future<void>.delayed(Duration.zero);

      realtime.add(
        InboxPostChanged(postId: 'realtime', candidate: _candidate('realtime')),
      );
      await _waitUntil(
        () => container
            .read(inboxSessionProvider)
            .requireValue
            .snapshot
            .newItems
            .any((InboxItem item) => item.postIds.contains('realtime')),
      );

      final InboxPageViewState rebuiltPage = container.read(inboxPageProvider);
      expect(rebuiltPage.selectedTab, InboxPageTab.newItems);
      expect(rebuiltPage.postponedScrollOffset, 0);
      expect(rebuiltPage.focusedItemKey, isNull);
      expect(
        container
            .read(inboxSessionProvider)
            .requireValue
            .snapshot
            .newMessageCount,
        1,
      );
    },
  );
}

final AuthSession _session = AuthSession(
  serverUrl: Uri.parse('https://chat.example.test'),
  userId: 'me',
  username: 'me',
);

InboxPostCandidate _candidate(String id) => InboxPostCandidate(
  post: Post(
    id: id,
    channelId: 'channel',
    author: const PostAuthor(id: 'other', displayName: 'Other'),
    sentAt: DateTime.utc(2026),
    message: id,
  ),
  channel: const SidebarChannel(
    id: 'channel',
    teamId: 'team',
    name: 'channel',
    displayName: 'Channel',
    kind: ChannelKind.publicChannel,
  ),
  reason: InboxAttentionReason.directMention,
);

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached');
}

final class _InboxRepository extends InboxRepository {
  const _InboxRepository(this.realtime);

  final Stream<InboxRealtimeEvent> realtime;

  @override
  Future<InboxSnapshot> load({required AuthSession session}) async =>
      InboxSnapshot();

  @override
  Stream<InboxRealtimeEvent> watch({required AuthSession session}) => realtime;

  @override
  Future<void> markRead({
    required AuthSession session,
    required InboxItem item,
  }) async {}
}

final class _PostponedRepository extends PostponedRepository {
  const _PostponedRepository();

  @override
  Future<PostponedReferencesSnapshot> load({
    required AuthSession session,
  }) async => PostponedReferencesSnapshot(const <PostponedReference>[]);

  @override
  Future<void> remove({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {}

  @override
  Future<void> save({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {}
}
