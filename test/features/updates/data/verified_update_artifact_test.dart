import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/updates/data/verified_update_artifact.dart';
import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';

void main() {
  test('accepts an exact byte count and SHA-256 digest', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'mattermost-update-verifier-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final File file = File('${directory.path}/update.apk');
    final List<int> bytes = 'verified update'.codeUnits;
    await file.writeAsBytes(bytes);

    await verifyUpdateArtifactFile(file.path, _artifact(bytes));
  });

  test('rejects a checksum mismatch', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'mattermost-update-verifier-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final File file = File('${directory.path}/update.apk');
    final List<int> bytes = 'tampered update'.codeUnits;
    await file.writeAsBytes(bytes);

    expect(
      () => verifyUpdateArtifactFile(
        file.path,
        UpdateArtifact(
          name: 'update.apk',
          downloadUrl: Uri.parse('https://github.com/example/update.apk'),
          size: bytes.length,
          sha256: '0' * 64,
          abi: 'arm64-v8a',
        ),
      ),
      throwsA(
        isA<AppUpdateDownloadException>().having(
          (AppUpdateDownloadException error) => error.reason,
          'reason',
          'checksum_mismatch',
        ),
      ),
    );
  });

  test('rejects a size mismatch before hashing', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'mattermost-update-verifier-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final File file = File('${directory.path}/update.apk');
    final List<int> bytes = 'short'.codeUnits;
    await file.writeAsBytes(bytes);
    final UpdateArtifact artifact = _artifact(bytes);

    expect(
      () => verifyUpdateArtifactFile(
        file.path,
        UpdateArtifact(
          name: artifact.name,
          downloadUrl: artifact.downloadUrl,
          size: bytes.length + 1,
          sha256: artifact.sha256,
          abi: artifact.abi,
        ),
      ),
      throwsA(
        isA<AppUpdateDownloadException>().having(
          (AppUpdateDownloadException error) => error.reason,
          'reason',
          'size_mismatch',
        ),
      ),
    );
  });
}

UpdateArtifact _artifact(List<int> bytes) => UpdateArtifact(
  name: 'update.apk',
  downloadUrl: Uri.parse('https://github.com/example/update.apk'),
  size: bytes.length,
  sha256: sha256.convert(bytes).toString(),
  abi: 'arm64-v8a',
);
