import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_server_discovery.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_auth_repository.dart';
import 'package:mattermost_flutter/src/data/storage/credential_store.dart';
import 'package:mattermost_flutter/src/domain/models/auth_failure.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';

void main() {
  test(
    'restores one account-scoped client and closes it on sign out',
    () async {
      final Uri serverUrl = Uri.parse('https://chat.example.com');
      final _CredentialStore store = _CredentialStore(
        credentials: (serverUrl: serverUrl, token: 'secret'),
      );
      final _ClientFactory factory = _ClientFactory();
      final MattermostAuthRepository repository = MattermostAuthRepository(
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
      expect((activeApi as _AuthApi).logoutCalls, 1);
      expect(factory.clients.single.closed, isTrue);
      expect(repository.api, isNull);
    },
  );

  test('clears local credentials when server logout fails', () async {
    final _CredentialStore store = _CredentialStore();
    final _AuthApi api = _AuthApi(failLogout: true);
    final MattermostAuthRepository repository = MattermostAuthRepository(
      credentialStore: store,
      clientFactory: _ClientFactory(api: api),
    );
    await repository.authenticateWithSessionToken(
      serverUrl: Uri.parse('https://chat.example.com'),
      token: 'secret',
    );

    await repository.signOut();

    expect(api.logoutCalls, 1);
    expect(store.clearCount, 1);
    expect(store.credentials, isNull);
    expect(repository.api, isNull);
  });

  test('closes the previous transport after switching servers', () async {
    final _CredentialStore store = _CredentialStore();
    final _ClientFactory factory = _ClientFactory();
    final MattermostAuthRepository repository = MattermostAuthRepository(
      credentialStore: store,
      clientFactory: factory,
    );

    await repository.authenticateWithSessionToken(
      serverUrl: Uri.parse('https://one.example.com'),
      token: 'one',
    );
    final _ApiClient first = factory.clients.single;
    expect(first.closed, isFalse);

    await repository.authenticateWithSessionToken(
      serverUrl: Uri.parse('https://two.example.com'),
      token: 'two',
    );

    expect(factory.clients, hasLength(2));
    expect(first.closed, isTrue);
    expect(repository.api, same(factory.clients.last.api));
    expect(factory.clients.last.closed, isFalse);
  });

  test('exchanges password credentials for a saved session token', () async {
    final _CredentialStore store = _CredentialStore();
    final _ServerLoginClient loginClient = _ServerLoginClient(token: 'session');
    final MattermostAuthRepository repository = MattermostAuthRepository(
      credentialStore: store,
      clientFactory: _ClientFactory(),
      serverLoginClientFactory: _ServerLoginFactory(loginClient),
    );

    final AuthSession session = await repository.authenticateWithPassword(
      serverUrl: Uri.parse('https://chat.example.com'),
      loginId: 'ada',
      password: 'secret-password',
    );

    expect(session.username, 'ada');
    expect(loginClient.loginId, 'ada');
    expect(loginClient.password, 'secret-password');
    expect(store.credentials?.token, 'session');
    expect(loginClient.closed, isTrue);
  });

  test(
    'clears expired credentials after a 401 and leaves no active client',
    () async {
      final _CredentialStore store = _CredentialStore(
        credentials: (
          serverUrl: Uri.parse('https://chat.example.com'),
          token: 'x',
        ),
      );
      final _ClientFactory factory = _ClientFactory(
        api: _ThrowingAuthApi(statusCode: 401),
      );
      final MattermostAuthRepository repository = MattermostAuthRepository(
        credentialStore: store,
        clientFactory: factory,
      );

      await expectLater(
        repository.restoreSession(),
        throwsA(
          isA<AuthFailure>().having(
            (AuthFailure failure) => failure.kind,
            'kind',
            AuthFailureKind.sessionExpired,
          ),
        ),
      );

      expect(store.clearCount, 1);
      expect(store.credentials, isNull);
      expect(factory.clients.single.closed, isTrue);
      expect(repository.api, isNull);
    },
  );

  test('preserves credentials after a network error while restoring', () async {
    final ({Uri serverUrl, String token}) credentials = (
      serverUrl: Uri.parse('https://chat.example.com'),
      token: 'x',
    );
    final _CredentialStore store = _CredentialStore(credentials: credentials);
    final _ClientFactory factory = _ClientFactory(api: _ThrowingAuthApi());
    final MattermostAuthRepository repository = MattermostAuthRepository(
      credentialStore: store,
      clientFactory: factory,
    );

    await expectLater(
      repository.restoreSession(),
      throwsA(
        isA<AuthFailure>().having(
          (AuthFailure failure) => failure.kind,
          'kind',
          AuthFailureKind.network,
        ),
      ),
    );

    expect(store.clearCount, 0);
    expect(store.credentials, credentials);
    expect(factory.clients.single.closed, isTrue);
    expect(repository.api, isNull);
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
  _ClientFactory({MattermostApi? api}) : _api = api ?? _AuthApi();

  final List<_ApiClient> clients = <_ApiClient>[];
  final MattermostApi _api;

  @override
  MattermostApiClient create({required Uri serverUrl, required String token}) {
    final _ApiClient client = _ApiClient(_api);
    clients.add(client);
    return client;
  }
}

final class _ApiClient implements MattermostApiClient {
  _ApiClient(this.api);

  @override
  final MattermostApi api;

  bool closed = false;

  @override
  void close() => closed = true;
}

final class _ServerLoginFactory
    implements MattermostServerDiscoveryClientFactory {
  _ServerLoginFactory(this.client);

  final _ServerLoginClient client;

  @override
  MattermostServerDiscoveryClient create({required Uri serverUrl}) => client;
}

final class _ServerLoginClient implements MattermostServerDiscoveryClient {
  _ServerLoginClient({required this.token});

  final String token;
  String? loginId;
  String? password;
  bool closed = false;

  @override
  void close() => closed = true;

  @override
  Future<MattermostClientConfigDto> getClientConfig() =>
      throw UnimplementedError();

  @override
  Future<String> login({
    required String loginId,
    required String password,
  }) async {
    this.loginId = loginId;
    this.password = password;
    return token;
  }
}

final class _AuthApi implements MattermostSessionApi {
  _AuthApi({this.failLogout = false});

  final bool failLogout;
  int logoutCalls = 0;

  @override
  Future<void> logout() async {
    logoutCalls += 1;
    if (failLogout) throw StateError('logout failed');
  }

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

final class _ThrowingAuthApi implements MattermostApi {
  _ThrowingAuthApi({this.statusCode});

  final int? statusCode;

  @override
  Future<MattermostUserDto> getCurrentUser() async {
    throw DioException(
      requestOptions: RequestOptions(path: '/users/me'),
      response: statusCode == null
          ? null
          : Response<void>(
              requestOptions: RequestOptions(path: '/users/me'),
              statusCode: statusCode,
            ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
