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
  @override
  Future<List<Draft>> listTeamDrafts(String teamId) => load.future;
  @override
  Future<Draft?> saveDraft(Draft draft) async => draft;
  @override
  Future<void> deleteDraft({required String channelId, String? rootId}) async {}
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
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repo.load.complete(const [
        Draft(channelId: 'channel', message: 'Draft message', updateAt: 100),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Town Square'), findsOneWidget);
      expect(find.text('Draft message'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      expect(selected, 'town-square');
      expect(tester.takeException(), isNull);
    });
  }
}
