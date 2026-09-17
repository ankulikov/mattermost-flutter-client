import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/group_mention.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_candidate.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_search_result.dart';
import 'package:mattermost_flutter/src/features/mentions/presentation/mention_autocomplete_controller.dart';
import 'package:mattermost_flutter/src/features/mentions/presentation/mention_suggestion_panel.dart';

void main() {
  testWidgets('shows users and groups together with a member-count badge', (
    WidgetTester tester,
  ) async {
    MentionSuggestion? selected;
    final MentionCandidate user = MentionCandidate(
      user: const UserSummary(
        id: 'ada-id',
        username: 'ada',
        firstName: 'Ada',
        lastName: 'Lovelace',
        nickname: '',
        position: '',
        email: '',
      ),
    );
    final GroupMentionCandidate group = GroupMentionCandidate(
      group: const GroupMention(
        id: 'backend-id',
        name: 'backend',
        displayName: 'Backend Team',
        memberCount: 18,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MentionSuggestionPanel(
              state: MentionAutocompleteState(
                status: MentionAutocompleteStatus.data,
                result: MentionSearchResult(
                  channelMembers: <MentionCandidate>[user],
                  groupMentions: <GroupMentionCandidate>[group],
                  notInChannel: const <MentionCandidate>[],
                ),
              ),
              highlightedIndex: 1,
              onSelected: (MentionSuggestion value) => selected = value,
              onHighlighted: (_) {},
              onRetry: () {},
              onDismissed: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Channel members'), findsOneWidget);
    expect(find.text('Group Mentions'), findsOneWidget);
    expect(
      find.text('@backend - Backend Team', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('18 members'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('mention-group-backend-id')),
    );
    expect(selected, same(group));
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses singular member label', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MentionSuggestionPanel(
              state: const MentionAutocompleteState(
                status: MentionAutocompleteStatus.data,
                result: MentionSearchResult(
                  channelMembers: <MentionCandidate>[],
                  groupMentions: <GroupMentionCandidate>[
                    GroupMentionCandidate(
                      group: GroupMention(
                        id: 'solo-id',
                        name: 'solo',
                        displayName: 'Solo',
                        memberCount: 1,
                      ),
                    ),
                  ],
                  notInChannel: <MentionCandidate>[],
                ),
              ),
              highlightedIndex: 0,
              onSelected: (_) {},
              onHighlighted: (_) {},
              onRetry: () {},
              onDismissed: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('1 member'), findsOneWidget);
  });

  for (final double width in <double>[320, 900]) {
    testWidgets('group row fits ${width.toInt()}px with large text', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: MentionSuggestionPanel(
                state: const MentionAutocompleteState(
                  status: MentionAutocompleteStatus.data,
                  result: MentionSearchResult(
                    channelMembers: <MentionCandidate>[],
                    groupMentions: <GroupMentionCandidate>[
                      GroupMentionCandidate(
                        group: GroupMention(
                          id: 'long-id',
                          name: 'very-long-backend-group-name',
                          displayName: 'A very long backend group display name',
                          memberCount: 256,
                        ),
                      ),
                    ],
                    notInChannel: <MentionCandidate>[],
                  ),
                ),
                highlightedIndex: 0,
                onSelected: (_) {},
                onHighlighted: (_) {},
                onRetry: () {},
                onDismissed: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('256 members'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
