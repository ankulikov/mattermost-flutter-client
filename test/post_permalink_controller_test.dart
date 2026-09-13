import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post_navigation.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/ui/posts/post_permalink_controller.dart';

void main() {
  test('resolves its post ID with the active session', () async {
    final _PermalinkRepository repository = _PermalinkRepository(
      target: _target('linked-post'),
    );
    final (:container, :provider) = _container(repository: repository);
    addTearDown(container.dispose);
    final ProviderSubscription<AsyncValue<PostNavigationTarget>> subscription =
        container.listen(provider('linked-post'), (_, _) {});
    addTearDown(subscription.close);

    expect(
      (await container.read(provider('linked-post').future)).linkedPostId,
      'linked-post',
    );
    expect(repository.postIds, <String>['linked-post']);
    expect(repository.sessions.single.userId, 'me');
  });

  test(
    'reports initial failure and retry resolves the same route target',
    () async {
      final _PermalinkRepository repository = _PermalinkRepository(
        error: StateError('post was not found'),
      );
      final (:container, :provider) = _container(repository: repository);
      addTearDown(container.dispose);
      final ProviderSubscription<AsyncValue<PostNavigationTarget>>
      subscription = container.listen(provider('post-1'), (_, _) {});
      addTearDown(subscription.close);

      await expectLater(
        container.read(provider('post-1').future),
        throwsStateError,
      );
      expect(container.read(provider('post-1')).hasError, isTrue);

      repository
        ..error = null
        ..target = _target('post-1');
      final PostPermalinkController controller = container.read(
        provider('post-1').notifier,
      );
      await controller.retry();

      expect(
        container.read(provider('post-1')).requireValue.linkedPostId,
        'post-1',
      );
      expect(repository.postIds, <String>['post-1', 'post-1']);
    },
  );

  test('fails explicitly when no active session is available', () async {
    final _PermalinkRepository repository = _PermalinkRepository(
      target: _target('post-1'),
    );
    final (:container, :provider) = _container(
      repository: repository,
      hasSession: false,
    );
    addTearDown(container.dispose);
    final ProviderSubscription<AsyncValue<PostNavigationTarget>> subscription =
        container.listen(provider('post-1'), (_, _) {});
    addTearDown(subscription.close);

    await expectLater(
      container.read(provider('post-1').future),
      throwsA(isA<StateError>()),
    );
    expect(repository.postIds, isEmpty);
  });

  test(
    'cancels in-flight resolution when its route provider is disposed',
    () async {
      final _PermalinkRepository repository = _PermalinkRepository(
        target: _target('post-1'),
      )..defer = true;
      final (:container, :provider) = _container(repository: repository);
      final ProviderSubscription<AsyncValue<PostNavigationTarget>>
      subscription = container.listen(provider('post-1'), (_, _) {});
      await _waitFor(() => repository.cancellations.isNotEmpty);

      container.dispose();
      subscription.close();

      expect(repository.cancellations.single?.isCancelled, isTrue);
    },
  );

  test('ignores a stale completion after the provider is rebuilt', () async {
    final _PermalinkRepository repository = _PermalinkRepository(
      target: _target('unused'),
    )..defer = true;
    final (:container, :provider) = _container(repository: repository);
    addTearDown(container.dispose);
    final ProviderSubscription<AsyncValue<PostNavigationTarget>> subscription =
        container.listen(provider('post-1'), (_, _) {});
    addTearDown(subscription.close);
    await _waitFor(() => repository.pending.length == 1);

    container.invalidate(provider('post-1'));
    await _waitFor(() => repository.pending.length == 2);
    repository.pending[1].complete(_target('fresh'));
    await _waitFor(() => container.read(provider('post-1')).hasValue);

    repository.pending[0].complete(_target('stale'));
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(provider('post-1')).requireValue.linkedPostId,
      'fresh',
    );
  });
}

({
  ProviderContainer container,
  AsyncNotifierProviderFamily<
    PostPermalinkController,
    PostNavigationTarget,
    String
  >
  provider,
})
_container({
  required _PermalinkRepository repository,
  AuthSession? session,
  bool hasSession = true,
}) {
  final Provider<AuthSession?> sessionProvider = Provider<AuthSession?>((_) {
    if (!hasSession) return null;
    return session ??
        AuthSession(
          serverUrl: Uri.parse('https://chat.example.com'),
          userId: 'me',
          username: 'ada',
        );
  });
  final Provider<PostRepository> repositoryProvider = Provider<PostRepository>(
    (_) => repository,
  );
  final AsyncNotifierProviderFamily<
    PostPermalinkController,
    PostNavigationTarget,
    String
  >
  provider = AsyncNotifierProvider.autoDispose.family(
    (String postId) =>
        PostPermalinkController(postId, sessionProvider, repositoryProvider),
  );
  return (container: ProviderContainer(), provider: provider);
}

PostNavigationTarget _target(String postId) => PostNavigationTarget(
  linkedPostId: postId,
  channelPostId: 'root-$postId',
  channel: const SidebarChannel(
    id: 'channel-1',
    teamId: 'team-1',
    name: 'town-square',
    displayName: 'Town Square',
    kind: ChannelKind.publicChannel,
  ),
);

Future<void> _waitFor(bool Function() predicate) async {
  for (int attempt = 0; attempt != 20; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Timed out waiting for the asynchronous provider operation.');
}

final class _PermalinkRepository extends PostRepository {
  _PermalinkRepository({this.target, this.error});

  PostNavigationTarget? target;
  Object? error;
  bool defer = false;
  final List<String> postIds = <String>[];
  final List<AuthSession> sessions = <AuthSession>[];
  final List<RequestCancellation?> cancellations = <RequestCancellation?>[];
  final List<Completer<PostNavigationTarget>> pending =
      <Completer<PostNavigationTarget>>[];

  @override
  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  }) async => const ChannelPostPage();

  @override
  Future<ChannelPostPage> loadOlder({
    required AuthSession session,
    required String channelId,
    required String beforePostId,
  }) async => const ChannelPostPage();

  @override
  Future<PostNavigationTarget> resolveNavigationTarget({
    required AuthSession session,
    required String postId,
  }) {
    postIds.add(postId);
    sessions.add(session);
    cancellations.add(RequestCancellation.current);
    final Object? resolutionError = error;
    if (resolutionError != null) {
      return Future<PostNavigationTarget>.error(resolutionError);
    }
    if (defer) {
      final Completer<PostNavigationTarget> result =
          Completer<PostNavigationTarget>();
      pending.add(result);
      return result.future;
    }
    return Future<PostNavigationTarget>.value(target!);
  }
}
