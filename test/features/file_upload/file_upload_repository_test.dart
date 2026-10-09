import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/file_upload/data/mattermost_file_upload_repository.dart';
import 'package:mattermost_flutter/src/features/file_upload/domain/file_upload.dart';

void main() {
  for (final (status, failure) in <(int, UploadFailure)>[
    (413, UploadFailure.tooLarge),
    (401, UploadFailure.unauthorized),
    (403, UploadFailure.forbidden),
    (429, UploadFailure.rateLimited),
  ]) {
    test('maps upload HTTP $status to a safe failure', () async {
      final repository = MattermostFileUploadRepository(_Api(status));
      await expectLater(
        repository.upload(
          channelId: 'channel',
          file: _file,
          cancellation: RequestCancellation(),
          onProgress: (_, _) {},
        ),
        throwsA(
          isA<UploadException>().having((e) => e.failure, 'failure', failure),
        ),
      );
    });
  }

  test('rejects an unknown length without opening the source', () async {
    var opened = false;
    final repository = MattermostFileUploadRepository(_Api(200));
    await expectLater(
      repository.upload(
        channelId: 'channel',
        file: SelectedUploadFile(
          name: 'file',
          size: -1,
          openStream: () {
            opened = true;
            return const Stream<Uint8List>.empty();
          },
        ),
        cancellation: RequestCancellation(),
        onProgress: (_, _) {},
      ),
      throwsA(
        isA<UploadException>().having(
          (e) => e.failure,
          'failure',
          UploadFailure.invalidFile,
        ),
      ),
    );
    expect(opened, isFalse);
  });
}

final _file = SelectedUploadFile(
  name: 'file',
  size: 1,
  openStream: () => Stream<Uint8List>.value(Uint8List.fromList(<int>[1])),
);

final class _Api extends Fake implements MattermostApi {
  _Api(this.status);
  final int status;

  @override
  Future<String> uploadFile({
    required String channelId,
    required String name,
    required int length,
    required Stream<Uint8List> stream,
    required void Function(int sent, int total) onProgress,
  }) async {
    final options = RequestOptions(path: '/files');
    throw DioException(
      requestOptions: options,
      response: Response<Object?>(
        requestOptions: options,
        statusCode: status,
        headers: Headers.fromMap(<String, List<String>>{
          'retry-after': <String>['2'],
        }),
      ),
    );
  }
}
