import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/features/auth/data/credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/data/pat_auth_repository.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';

void main() {
  test(
    'restores one account-scoped client and closes it on sign out',
    () async {
      final Uri serverUrl = Uri.parse('https://chat.example.com');
      final _CredentialStore store = _CredentialStore(
        credentials: (serverUrl: serverUrl, token: 'secret'),
      );
      final _ClientFactory factory = _ClientFactory();
      final PatAuthRepository repository = PatAuthRepository(
        credentialStore: store,
        clientFactory: factory,
      );

      final AuthSession? session = await repository.restoreSession();
      final MattermostApi? activeApi = repository.api;

      expect(session?.serverUrl, serverUrl);
      expect(store.readCount, 1);
      expect(factory.clients, hasLength(1));
      expect(activeApi, same(factory.clients.single.api));

      await repository.signOut();

      expect(store.clearCount, 1);
      expect(factory.clients.single.closed, isTrue);
      expect(repository.api, isNull);
    },
  );

  test('closes the previous transport after switching servers', () async {
    final _CredentialStore store = _CredentialStore();
    final _ClientFactory factory = _ClientFactory();
    final PatAuthRepository repository = PatAuthRepository(
      credentialStore: store,
      clientFactory: factory,
    );

    await repository.authenticateWithPersonalAccessToken(
      serverUrl: Uri.parse('https://one.example.com'),
      token: 'one',
    );
    final _ApiClient first = factory.clients.single;
    expect(first.closed, isFalse);

    await repository.authenticateWithPersonalAccessToken(
      serverUrl: Uri.parse('https://two.example.com'),
      token: 'two',
    );

    expect(factory.clients, hasLength(2));
    expect(first.closed, isTrue);
    expect(repository.api, same(factory.clients.last.api));
    expect(factory.clients.last.closed, isFalse);
  });
}

final class _CredentialStore implements CredentialStore {
  _CredentialStore({this.credentials});

  ({Uri serverUrl, String token})? credentials;
  int readCount = 0;
  int clearCount = 0;

  @override
  Future<void> clear() async {
    clearCount += 1;
    credentials = null;
  }

  @override
  Future<({Uri serverUrl, String token})?> read() async {
    readCount += 1;
    return credentials;
  }

  @override
  Future<void> save({required Uri serverUrl, required String token}) async {
    credentials = (serverUrl: serverUrl, token: token);
  }
}

final class _ClientFactory implements MattermostApiClientFactory {
  final List<_ApiClient> clients = <_ApiClient>[];

  @override
  MattermostApiClient create({required Uri serverUrl, required String token}) {
    final _ApiClient client = _ApiClient();
    clients.add(client);
    return client;
  }
}

final class _ApiClient implements MattermostApiClient {
  @override
  final MattermostApi api = _AuthApi();

  bool closed = false;

  @override
  void close() => closed = true;
}

final class _AuthApi implements MattermostApi {
  @override
  Future<void> updateThreadRead({
    required String userId,
    required String teamId,
    required String threadId,
    required int timestamp,
  }) => throw UnimplementedError();

  @override
  Future<MattermostPostDto> createPost(MattermostCreatePostRequestDto post) =>
      throw UnimplementedError();

  @override
  Future<MattermostImageDto> getUserProfileImage({
    required String userId,
    int lastPictureUpdate = 0,
  }) => throw UnimplementedError();

  @override
  Future<MattermostUserDto> getCurrentUser() async =>
      const MattermostUserDto(id: 'user-1', username: 'ada');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
