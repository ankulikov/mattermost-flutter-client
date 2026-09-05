import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/data/providers/session_providers.dart';
import 'package:mattermost_flutter/src/data/session/active_account_context.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';

void main() {
  test(
    'deactivating an active account invalidates its API without a cycle',
    () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final ActiveAccountContext context = container.read(
        activeAccountContextProvider,
      );
      final _ApiClient client = _ApiClient();

      context.activate(
        client: client,
        session: AuthSession(
          serverUrl: Uri.parse('https://chat.example.com'),
          userId: 'user-1',
          username: 'ada',
        ),
      );

      expect(container.read(activeMattermostApiProvider), same(client.api));

      context.deactivate();

      expect(client.closed, isTrue);
      expect(container.read(activeAccountSessionProvider), isNull);
      expect(
        () => container.read(activeMattermostApiProvider),
        throwsA(isA<Object>()),
      );
    },
  );
}

final class _ApiClient implements MattermostApiClient {
  @override
  final MattermostApi api = _Api();

  bool closed = false;

  @override
  void close() => closed = true;
}

final class _Api extends Fake implements MattermostApi {}
