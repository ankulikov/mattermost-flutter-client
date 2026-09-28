import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_completeness.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_source_result.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/assemble_inbox_projection.dart';

void main() {
  const InboxProjectionAssembler assembler = InboxProjectionAssembler();

  test('combines source completeness and reconciles postponed candidates', () {
    final InboxPostCandidate candidate = _candidate('post');
    final InboxSnapshot snapshot = assembler.assemble(
      builtAt: DateTime.utc(2026, 9, 26),
      sources: <InboxSourceResult>[
        InboxSourceResult(
          candidates: InboxSourceSnapshot(
            posts: <InboxPostCandidate>[candidate],
          ),
          completeness: InboxCompleteness.approximateMentions,
          diagnosticsCodes: const <InboxSourceDiagnosticCode>[
            InboxSourceDiagnosticCode.mentionReconstructionMismatch,
          ],
        ),
        InboxSourceResult(
          candidates: InboxSourceSnapshot(),
          postponedItems: <InboxItem>[
            ChannelPostInboxItem(
              candidate: candidate,
              postponedAt: DateTime.utc(2026, 9, 25),
            ),
          ],
        ),
      ],
    );

    expect(snapshot.newItems, isEmpty);
    expect(snapshot.postponedItems.single.postIds, <String>['post']);
    expect(snapshot.completeness, InboxCompleteness.approximateMentions);
    expect(
      snapshot.diagnosticsCodes,
      contains(InboxSourceDiagnosticCode.mentionReconstructionMismatch),
    );
  });
}

InboxPostCandidate _candidate(String id) => InboxPostCandidate(
  post: Post(
    id: id,
    channelId: 'channel',
    author: const PostAuthor(id: 'other', displayName: 'Other'),
    sentAt: DateTime.utc(2026, 9, 26),
    message: id,
  ),
  channel: SidebarChannel(
    id: 'channel',
    teamId: 'team',
    name: 'channel',
    displayName: 'Channel',
    kind: ChannelKind.publicChannel,
  ),
  reason: InboxAttentionReason.directMention,
);
