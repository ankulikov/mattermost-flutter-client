import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_settings.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_source_result.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/assemble_inbox_projection.dart';

void main() {
  const InboxProjectionAssembler assembler = InboxProjectionAssembler();
  final DateTime start = DateTime.utc(2026, 9, 27);

  InboxSnapshot assemble(InboxDirectGroupingSettings settings) =>
      assembler.assemble(
        directGrouping: settings,
        sources: <InboxSourceResult>[
          InboxSourceResult(
            candidates: InboxSourceSnapshot(
              posts: <InboxPostCandidate>[
                _candidate(id: 'one', at: start),
                _candidate(
                  id: 'two',
                  at: start.add(const Duration(seconds: 30)),
                  authorId: 'another',
                ),
                _candidate(
                  id: 'three',
                  at: start.add(const Duration(minutes: 10)),
                ),
              ],
            ),
          ),
        ],
      );

  group('Inbox direct grouping settings', () {
    test('defaults to the bounded consecutive 120-second policy', () {
      final InboxSnapshot snapshot = assembler.assemble(
        sources: <InboxSourceResult>[
          InboxSourceResult(
            candidates: InboxSourceSnapshot(
              posts: <InboxPostCandidate>[
                _candidate(id: 'one', at: start),
                _candidate(
                  id: 'two',
                  at: start.add(const Duration(seconds: 120)),
                ),
              ],
            ),
          ),
        ],
      );

      expect(snapshot.newItems.single.postIds, <String>['one', 'two']);
    });

    test('none keeps every direct message as an individual item', () {
      final InboxSnapshot snapshot = assemble(
        const InboxDirectGroupingSettings(mode: InboxDirectGroupingMode.none),
      );

      expect(snapshot.newItems, hasLength(3));
      expect(
        snapshot.newItems.map((InboxItem item) => item.postIds),
        containsAll(<List<String>>[
          <String>['one'],
          <String>['two'],
          <String>['three'],
        ]),
      );
    });

    test(
      'consecutive applies the persisted window between adjacent messages',
      () {
        final InboxSnapshot snapshot = assemble(
          const InboxDirectGroupingSettings(
            mode: InboxDirectGroupingMode.consecutive,
            windowSeconds: 15,
          ),
        );

        expect(snapshot.newItems, hasLength(3));
      },
    );

    test('conversation retains compatible messages across a time gap', () {
      final InboxSnapshot snapshot = assemble(
        const InboxDirectGroupingSettings(
          mode: InboxDirectGroupingMode.conversation,
          windowSeconds: 1,
        ),
      );

      expect(snapshot.newItems, hasLength(2));
      expect(
        snapshot.newItems
            .map((InboxItem item) => item.postIds.join(','))
            .toList(),
        contains('one,three'),
      );
      expect(
        snapshot.newItems
            .map((InboxItem item) => item.postIds.join(','))
            .toList(),
        contains('two'),
      );
    });
  });
}

InboxPostCandidate _candidate({
  required String id,
  required DateTime at,
  String authorId = 'other',
}) => InboxPostCandidate(
  post: Post(
    id: id,
    channelId: 'dm',
    author: PostAuthor(id: authorId, displayName: authorId),
    sentAt: at,
    message: id,
  ),
  channel: const SidebarChannel(
    id: 'dm',
    teamId: 'team',
    name: 'dm',
    displayName: 'DM',
    kind: ChannelKind.directMessage,
  ),
  reason: InboxAttentionReason.allMessagesSubscription,
);
