import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft_repository.dart';
import 'package:mattermost_flutter/src/features/drafts/presentation/drafts_controller.dart';
import 'package:mattermost_flutter/src/features/drafts/presentation/drafts_pane.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

class _Repository implements DraftRepository {
  final Completer<List<Draft>> load = Completer<List<Draft>>();
  final deleted = <String>[];
  @override
  Future<List<Draft>> listTeamDrafts(String teamId) => load.future;
  @override
  Future<Draft?> saveDraft(Draft draft) async => draft;
  @override
  Future<void> deleteDraft({required String channelId, String? rootId}) async {
    deleted.add('$channelId:${rootId ?? ''}');
  }
}

void main() {
  for (final width in <double>[390, 1200]) {
    testWidgets('draft list loads and opens its channel at width $width', (
      tester,
    ) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _Repository();
      final session = Provider<AuthSession?>(
        (ref) => AuthSession(
          serverUrl: Uri.parse('https://example.test'),
          userId: 'user',
          username: 'user',
        ),
      );
      final repository = Provider<DraftRepository>((ref) => repo);
      String? selected;
      const channel = SidebarChannel(
        id: 'channel',
        teamId: 'team',
        name: 'town-square',
        displayName: 'Town Square',
        kind: ChannelKind.publicChannel,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            draftsControllerProvider.overrideWith(
              () => DraftsController(session, repository),
            ),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
              child: Scaffold(
                body: DraftsPane(
                  team: const SidebarTeam(id: 'team', displayName: 'Team'),
                  channelsById: const {'channel': channel},
                  onSelectChannel: (value) => selected = value,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      expect(find.text('Drafts'), findsOneWidget);
      expect(
        find.text("Any messages you've started will show here"),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.text('Drafts')).style?.fontWeight,
        FontWeight.w700,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repo.load.complete([
        Draft(
          channelId: 'channel',
          message: 'Draft message',
          updateAt: DateTime.now()
              .subtract(const Duration(minutes: 55, seconds: 30))
              .millisecondsSinceEpoch,
        ),
        const Draft(
          channelId: 'channel',
          rootId: 'root',
          message: 'Thread draft',
          updateAt: 50,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Town Square'), findsOneWidget);
      expect(find.text('Draft message'), findsOneWidget);
      expect(find.text('55 minutes ago'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('55 minutes ago')).dx,
        greaterThan(tester.getTopLeft(find.text('Town Square')).dx),
      );
      final bar = tester.widget<OverflowBar>(find.byType(OverflowBar).first);
      expect(bar.alignment, MainAxisAlignment.end);
      expect(find.text('Town Square · Thread'), findsOneWidget);
      expect(find.text('TS'), findsNWidgets(2));
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
      expect(find.byIcon(Icons.send_outlined), findsNWidgets(2));
      final delete = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Delete').first,
      );
      expect(
        delete.style!.foregroundColor!.resolve({}),
        Theme.of(tester.element(find.text('Delete').first)).colorScheme.error,
      );
      await tester.tap(find.text('Town Square'));
      expect(selected, 'town-square');
      await tester.tap(find.text('Delete').first);
      await tester.pumpAndSettle();
      expect(find.text('Delete draft'), findsOneWidget);
      expect(
        find.text('Are you sure you want to delete this draft to Town Square?'),
        findsOneWidget,
      );
      expect(repo.deleted, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.deleted, isEmpty);
      expect(find.text('Draft message'), findsOneWidget);
      await tester.tap(find.text('Delete').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, delete'));
      await tester.pumpAndSettle();
      expect(repo.deleted, ['channel:']);
      expect(find.text('Draft message'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
