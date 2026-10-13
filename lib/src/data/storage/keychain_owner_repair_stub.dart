import 'package:mattermost_flutter/src/data/storage/keychain_repair_result.dart';

Future<KeychainRepairResult> repairInaccessibleMacOsKeychainItem({
  required String key,
  required String service,
}) async => KeychainRepairResult.failed;
