import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft_repository.dart';
import 'package:mattermost_flutter/src/features/drafts/presentation/draft_send_controller.dart';
import 'package:mattermost_flutter/src/features/drafts/presentation/drafts_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = DraftKey(channelId: 'channel');
  const draft = Draft(channelId: 'channel', message: 'hello');
  late _Drafts drafts;
  late _Posts posts;
  late ProviderContainer container;
  late NotifierProvider<DraftsController, DraftsState> draftsProvider;
  late NotifierProvider<DraftSendController, Map<DraftKey, DraftSendStatus>>
  sender;
  setUp(() {
    drafts = _Drafts();
    posts = _Posts();
    final session = Provider<AuthSession?>(
      (ref) => AuthSession(
        serverUrl: Uri.parse('https://example.test'),
        userId: 'user',
        username: 'user',
      ),
    );
    final draftRepo = Provider<DraftRepository>((ref) => drafts);
    final postRepo = Provider<PostRepository>((ref) => posts);
    draftsProvider = NotifierProvider(
      () => DraftsController(session, draftRepo),
    );
    sender = NotifierProvider(
      () => DraftSendController(session, postRepo, draftsProvider),
    );
    container = ProviderContainer();
    container.read(draftsProvider.notifier).update(draft);
  });
  tearDown(() => container.dispose());

  test(
    'successful send followed by failed cleanup retries only deletion',
    () async {
      drafts.failDelete = true;
      await container.read(sender.notifier).send(key);
      expect(posts.ids.length, 1);
      expect(container.read(sender)[key]?.phase, DraftSendPhase.cleanupPending);
      drafts.failDelete = false;
      await container.read(sender.notifier).send(key);
      expect(posts.ids.length, 1);
      expect(drafts.deletes, 2);
      expect(container.read(draftsProvider).entries, isEmpty);
    },
  );

  test('failed post retry reuses pending ID', () async {
    posts.fail = true;
    await container.read(sender.notifier).send(key);
    posts.fail = false;
    await container.read(sender.notifier).send(key);
    expect(posts.ids.length, 2);
    expect(posts.ids.first, posts.ids.last);
  });

  test('preserves newer draft and blocks duplicate send', () async {
    posts.completer = Completer<ChannelPost>();
    final first = container.read(sender.notifier).send(key);
    await container.read(sender.notifier).send(key);
    expect(posts.ids.length, 1);
    container
        .read(draftsProvider.notifier)
        .update(const Draft(channelId: 'channel', message: 'new'));
    posts.completer!.complete(_post());
    await first;
    expect(container.read(draftsProvider).entries[key]?.draft.message, 'new');
    expect(drafts.deletes, 0);
  });
}

ChannelPost _post() => Post(
  id: 'post',
  channelId: 'channel',
  author: const PostAuthor(id: 'u', displayName: 'U'),
  sentAt: DateTime(2026),
  message: 'hello',
);

final class _Drafts implements DraftRepository {
  bool failDelete = false;
  int deletes = 0;
  @override
  Future<void> deleteDraft({required String channelId, String? rootId}) async {
    deletes++;
    if (failDelete) throw StateError('unavailable');
  }

  @override
  Future<List<Draft>> listTeamDrafts(String teamId) async => [];
  @override
  Future<Draft?> saveDraft(Draft draft) async => draft;
}

final class _Posts extends Fake implements PostRepository {
  bool fail = false;
  Completer<ChannelPost>? completer;
  final ids = <String>[];
  @override
  Future<ChannelPost> sendPost({
    required AuthSession session,
    required String channelId,
    required String message,
    required String pendingPostId,
    String rootPostId = '',
    List<String> fileIds = const [],
  }) async {
    ids.add(pendingPostId);
    if (fail) throw StateError('unavailable');
    return completer?.future ?? _post();
  }
}
