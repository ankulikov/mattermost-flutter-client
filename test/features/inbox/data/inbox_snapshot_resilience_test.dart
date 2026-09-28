import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/data/repositories/mattermost_inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_completeness.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';

void main() {
  final AuthSession session = AuthSession(
    serverUrl: Uri.parse('https://chat.example.test'),
    userId: 'me',
    username: 'me',
  );

  test(
    'retries one rate-limited snapshot request within a bounded budget',
    () async {
      final _SnapshotApi api = _SnapshotApi(
        rateLimitFirstCurrentUserRequest: true,
      );

      final result = await _repository(
        api,
        const _Postponed(),
      ).load(session: session);

      expect(api.currentUserRequests, 2);
      expect(result.sourceFailures, isEmpty);
    },
  );

  test('publishes a scoped, content-free partial source failure', () async {
    final _SnapshotApi api = _SnapshotApi();

    final result = await _repository(
      api,
      const _FailingPostponed(),
    ).load(session: session);

    expect(result.completeness, InboxCompleteness.truncated);
    expect(
      result.diagnosticsCodes,
      contains(InboxSourceDiagnosticCode.sourceRequestFailed),
    );
    expect(
      result.sourceFailures,
      contains(const InboxSourceFailure(scope: InboxSourceScope.postponed)),
    );
  });
}

MattermostInboxRepository _repository(
  MattermostApi api,
  PostponedRepository postponed,
) => MattermostInboxRepository(
  api: api,
  messageMapper: const MattermostMessageMapper(),
  postponed: postponed,
);

final class _SnapshotApi extends Fake implements MattermostApi {
  _SnapshotApi({this.rateLimitFirstCurrentUserRequest = false});

  final bool rateLimitFirstCurrentUserRequest;
  var currentUserRequests = 0;

  @override
  Future<MattermostUserDto> getCurrentUser() async {
    currentUserRequests++;
    if (rateLimitFirstCurrentUserRequest && currentUserRequests == 1) {
      throw const MattermostRateLimitException(retryAfter: Duration.zero);
    }
    return const MattermostUserDto(id: 'me', username: 'me');
  }

  @override
  Future<List<MattermostTeamDto>> getTeamsForCurrentUser() async =>
      const <MattermostTeamDto>[];
}

final class _Postponed extends PostponedRepository {
  const _Postponed();

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

final class _FailingPostponed extends PostponedRepository {
  const _FailingPostponed();

  @override
  Future<PostponedReferencesSnapshot> load({required AuthSession session}) =>
      Future<PostponedReferencesSnapshot>.error(StateError('unavailable'));

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
