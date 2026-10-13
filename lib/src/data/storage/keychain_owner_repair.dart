import 'package:mattermost_flutter/src/data/storage/keychain_owner_repair_stub.dart'
    if (dart.library.io) 'package:mattermost_flutter/src/data/storage/keychain_owner_repair_io.dart'
    as platform;
import 'package:mattermost_flutter/src/data/storage/keychain_repair_result.dart';

Future<KeychainRepairResult> repairInaccessibleMacOsKeychainItem({
  required String key,
  required String service,
}) => platform.repairInaccessibleMacOsKeychainItem(key: key, service: service);
