import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/storage/keychain_repair_result.dart';
import 'package:mattermost_flutter/src/data/storage/secure_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final Map<String, String> values = <String, String>{};
  final List<String> deletedKeys = <String>[];
  final List<String> repairedKeys = <String>[];
  String? failingDeleteKey;
  bool failMissingDelete = false;
  KeychainRepairResult repairResult = KeychainRepairResult.removed;

  Future<KeychainRepairResult> repair({
    required String key,
    required String service,
  }) async {
    expect(service, 'flutter_secure_storage_service');
    repairedKeys.add(key);
    if (repairResult == KeychainRepairResult.removed) values.remove(key);
    return repairResult;
  }

  SecureCredentialStore createStore() =>
      SecureCredentialStore(keychainOwnerRepair: repair);

  setUp(() {
    values.clear();
    deletedKeys.clear();
    repairedKeys.clear();
    failingDeleteKey = null;
    failMissingDelete = false;
    repairResult = KeychainRepairResult.removed;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          final String key =
              (call.arguments as Map<Object?, Object?>)['key'] as String;
          if (call.method == 'read') return values[key];
          if (call.method == 'delete') {
            deletedKeys.add(key);
            if ((failMissingDelete && !values.containsKey(key)) ||
                key == failingDeleteKey) {
              throw PlatformException(
                code: 'Unexpected security result code',
                message: 'Invalid attempt to change the owner of this item.',
                details: -25244,
              );
            }
            values.remove(key);
            return null;
          }
          throw UnsupportedError(call.method);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('clears a current session when the legacy key is absent', () async {
    values.addAll(<String, String>{
      'mattermost.active.server_url': 'https://chat.example.com',
      'mattermost.active.session_token': 'token',
    });

    await createStore().clear();

    expect(values, isEmpty);
    expect(deletedKeys, <String>[
      'mattermost.active.session_token',
      'mattermost.active.personal_access_token',
      'mattermost.active.server_url',
    ]);
    expect(repairedKeys, isEmpty);
  });

  test('clears a migrated legacy token as well', () async {
    values.addAll(<String, String>{
      'mattermost.active.server_url': 'https://chat.example.com',
      'mattermost.active.personal_access_token': 'legacy-token',
    });

    await createStore().clear();

    expect(values, isEmpty);
    expect(deletedKeys, <String>[
      'mattermost.active.session_token',
      'mattermost.active.personal_access_token',
      'mattermost.active.server_url',
    ]);
    expect(repairedKeys, isEmpty);
  });

  test(
    'treats a missing key as cleared if macOS rejects its deletion',
    () async {
      failMissingDelete = true;
      repairResult = KeychainRepairResult.absent;
      await createStore().clear();

      expect(deletedKeys, hasLength(3));
      expect(repairedKeys, hasLength(3));
    },
  );

  test('repairs a token owned by an old macOS Keychain ACL', () async {
    values['mattermost.active.session_token'] = 'token';
    failingDeleteKey = 'mattermost.active.session_token';

    await createStore().clear();

    expect(values, isEmpty);
    expect(repairedKeys, <String>['mattermost.active.session_token']);
  });

  test('reports a token that cannot be deleted or repaired', () async {
    values['mattermost.active.session_token'] = 'token';
    failingDeleteKey = 'mattermost.active.session_token';
    repairResult = KeychainRepairResult.failed;

    await expectLater(createStore().clear(), throwsA(isA<PlatformException>()));

    expect(values['mattermost.active.session_token'], 'token');
    expect(repairedKeys, <String>['mattermost.active.session_token']);
  });
}
