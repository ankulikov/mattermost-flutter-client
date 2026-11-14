import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft_realtime.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft_repository.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft_sync_preference.dart';
import 'package:mattermost_flutter/src/features/drafts/presentation/drafts_controller.dart';

class FakeDraftRepository implements DraftRepository {
  Completer<List<Draft>>? load;
  Completer<Draft?>? save;
  bool failDelete = false;
  int transientDeletes = 0;
  final calls = <String>[];
  @override
  Future<List<Draft>> listTeamDrafts(String teamId) => load!.future;
  @override
  Future<Draft?> saveDraft(Draft draft) {
    calls.add('save');
    return save!.future;
  }

  @override
  Future<void> deleteDraft({required String channelId, String? rootId}) async {
    calls.add('delete');
    if (transientDeletes > 0) {
      transientDeletes--;
      throw const DraftSyncException(
        retryable: true,
        retryAfter: Duration.zero,
      );
    }
    if (failDelete) throw StateError('delete failed');
  }
}

class FakeSyncPreference implements DraftSyncPreference {
  FakeSyncPreference(this.enabled);
  final bool enabled;
  @override
  Future<bool> isEnabled(String userId) async => enabled;
}

class FakeRealtime implements DraftRealtime {
  final stream = StreamController<DraftRealtimeChange>.broadcast();
  Future<void> close() => stream.close();
  @override
  Stream<DraftRealtimeChange> watch(AuthSession session) => stream.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const local = Draft(channelId: 'channel', message: 'local');
  const remote = Draft(channelId: 'channel', message: 'remote');
  const key = DraftKey(channelId: 'channel');
  late FakeDraftRepository repository;
  late ProviderContainer container;
  late NotifierProvider<DraftsController, DraftsState> provider;
  setUp(() {
    repository = FakeDraftRepository();
    final session = Provider<AuthSession?>(
      (ref) => AuthSession(
        serverUrl: Uri.parse('https://example.test'),
        userId: 'user',
        username: 'user',
      ),
    );
    final repo = Provider<DraftRepository>((ref) => repository);
    provider = NotifierProvider(() => DraftsController(session, repo));
    container = ProviderContainer();
  });
  tearDown(() => container.dispose());

  testWidgets('syncs five seconds after the latest edit', (tester) async {
    repository.save = Completer<Draft?>()..complete(remote);
    final controller = container.read(provider.notifier);
    controller.update(local);
    await tester.pump(const Duration(seconds: 4));
    expect(repository.calls, isEmpty);

    controller.update(remote);
    await tester.pump(const Duration(milliseconds: 4999));
    expect(repository.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(repository.calls, ['save']);
  });

  test('late hydration preserves and saves the active draft', () async {
    repository.load = Completer<List<Draft>>();
    repository.save = Completer<Draft?>();
    final controller = container.read(provider.notifier);
    final loading = controller.loadTeam('team');
    controller.update(local);
    final flushing = controller.flush(key);
    repository.load!.complete([remote]);
    await loading;
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).entries[key]!.draft.message, 'local');
    expect(repository.calls, ['save']);
    repository.save!.complete(local);
    await flushing;
    expect(container.read(provider).entries[key]!.draft.message, 'local');
    expect(container.read(provider).entries[key]!.dirty, isFalse);
  });

  test('delete waits for a pending save', () async {
    repository.save = Completer<Draft?>();
    final controller = container.read(provider.notifier);
    controller.update(local);
    final saving = controller.flush(key);
    await Future<void>.delayed(Duration.zero);
    final deleting = controller.delete(key);
    expect(repository.calls, ['save']);
    repository.save!.complete(local);
    await saving;
    await deleting;
    expect(repository.calls, ['save', 'delete']);
    expect(container.read(provider).entries, isEmpty);
  });

  test(
    'failed cleanup retains the sent draft and reports the failure',
    () async {
      repository.failDelete = true;
      final controller = container.read(provider.notifier);
      controller.update(local);
      expect(await controller.deleteIfUnchanged(key, local), isFalse);
      expect(container.read(provider).entries[key]!.draft.message, 'local');
      expect(container.read(provider).entries[key]!.error, isNotNull);
      expect(container.read(provider).entries[key]!.cleanupPending, isTrue);
      await controller.flush(key);
      expect(repository.calls, ['delete']);
    },
  );

  test('transient deletes retry within the serialized operation', () async {
    repository.transientDeletes = 2;
    final controller = container.read(provider.notifier);
    controller.update(local);
    await controller.delete(key);
    expect(repository.calls, ['delete', 'delete', 'delete']);
    expect(container.read(provider).entries, isEmpty);
  });

  test('opted out drafts remain local and do not call the server', () async {
    final session = Provider<AuthSession?>(
      (ref) => AuthSession(
        serverUrl: Uri.parse('https://example.test'),
        userId: 'user',
        username: 'user',
      ),
    );
    final repo = Provider<DraftRepository>((ref) => repository);
    final preference = Provider<DraftSyncPreference>(
      (ref) => FakeSyncPreference(false),
    );
    final localProvider = NotifierProvider(
      () => DraftsController(session, repo, null, preference),
    );
    final controller = container.read(localProvider.notifier);
    controller.update(local);
    await controller.flush(key);
    expect(repository.calls, isEmpty);
    expect(container.read(localProvider).syncStatus, DraftSyncStatus.disabled);
    expect(container.read(localProvider).entries[key]!.draft.message, 'local');
  });

  test('preference realtime event invalidates the cached opt-out', () async {
    final realtime = FakeRealtime();
    final session = Provider<AuthSession?>(
      (ref) => AuthSession(
        serverUrl: Uri.parse('https://example.test'),
        userId: 'user',
        username: 'user',
      ),
    );
    final repo = Provider<DraftRepository>((ref) => repository);
    final preference = Provider<DraftSyncPreference>(
      (ref) => FakeSyncPreference(false),
    );
    final events = Provider<DraftRealtime>((ref) => realtime);
    final localProvider = NotifierProvider(
      () => DraftsController(session, repo, events, preference),
    );
    final controller = container.read(localProvider.notifier);
    controller.update(local);
    await controller.flush(key);
    expect(container.read(localProvider).syncStatus, DraftSyncStatus.disabled);
    realtime.stream.add(DraftRealtimeChange.preferences);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(localProvider).syncStatus, DraftSyncStatus.unknown);
    await realtime.close();
  });
}
