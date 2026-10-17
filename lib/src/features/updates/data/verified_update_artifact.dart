import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';

Future<void> verifyUpdateArtifactFile(
  String path,
  UpdateArtifact artifact,
) async {
  final File file = File(path);
  if (await file.length() != artifact.size) {
    throw const AppUpdateDownloadException('size_mismatch');
  }
  final String digest = await Isolate.run<String>(() async {
    final Digest value = await sha256.bind(File(path).openRead()).first;
    return value.toString();
  });
  if (digest.toLowerCase() != artifact.sha256.toLowerCase()) {
    throw const AppUpdateDownloadException('checksum_mismatch');
  }
}
