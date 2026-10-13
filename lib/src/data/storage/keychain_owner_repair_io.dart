import 'dart:io';

import 'package:mattermost_flutter/src/data/storage/keychain_repair_result.dart';

Future<KeychainRepairResult> repairInaccessibleMacOsKeychainItem({
  required String key,
  required String service,
}) async {
  if (!Platform.isMacOS) return KeychainRepairResult.failed;

  try {
    // The security tool runs with the user's Keychain access and can remove a
    // legacy item whose ACL rejects deletion by this app. No values are passed
    // to the process or included in diagnostics.
    // A failed plugin update may leave duplicate file-based Keychain items.
    // The utility deletes one matching item per invocation.
    bool removedAny = false;
    for (int attempt = 0; attempt < 8; attempt += 1) {
      final ProcessResult result = await Process.run(
        '/usr/bin/security',
        <String>['delete-generic-password', '-s', service, '-a', key],
      );
      if (result.exitCode == 44) {
        return removedAny
            ? KeychainRepairResult.removed
            : KeychainRepairResult.absent;
      }
      if (result.exitCode != 0) return KeychainRepairResult.failed;
      removedAny = true;
    }
    return KeychainRepairResult.failed;
  } on ProcessException {
    return KeychainRepairResult.failed;
  }
}
