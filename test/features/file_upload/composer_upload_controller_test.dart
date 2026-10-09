import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/features/file_upload/domain/file_upload.dart';
import 'package:mattermost_flutter/src/features/file_upload/presentation/composer_upload_controller.dart';

void main() {
  test(
    'bounds concurrent uploads, keeps order, and requires failed tile retry',
    () async {
      final repository = _Repository();
      final controller = ComposerUploadController(
        repository: repository,
        channelId: 'channel',
      );
      addTearDown(controller.dispose);
      expect(controller.addFiles(List.generate(3, _file)), isTrue);
      expect(repository.calls, hasLength(2));
      expect(controller.ready, isFalse);
      repository.calls[0].progress(4, 4);
      expect(controller.tiles.first.status, UploadTileStatus.finalizing);
      repository.calls[0].result.complete('id-0');
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls, hasLength(3));
      repository.calls[1].result.completeError(
        const UploadException(UploadFailure.tooLarge),
      );
      repository.calls[2].result.complete('id-2');
      await Future<void>.delayed(Duration.zero);
      expect(controller.ready, isFalse);
      expect(controller.tiles[1].failure, UploadFailure.tooLarge);
      controller.retry(controller.tiles[1].localId);
      expect(repository.calls, hasLength(4));
      repository.calls[3].result.complete('id-1');
      await Future<void>.delayed(Duration.zero);
      expect(controller.ready, isTrue);
      expect(controller.uploadedIds, <String>['id-0', 'id-1', 'id-2']);
      expect(controller.addFiles(List.generate(3, _file)), isFalse);
    },
  );

  test('remove cancels work and ignores a late result', () async {
    final repository = _Repository();
    final controller = ComposerUploadController(
      repository: repository,
      channelId: 'channel',
    );
    addTearDown(controller.dispose);
    controller.addFiles(<SelectedUploadFile>[_file(0)]);
    final int localId = controller.tiles.single.localId;
    controller.remove(localId);
    expect(repository.calls.single.cancellation.isCancelled, isTrue);
    repository.calls.single.result.complete('late-id');
    await Future<void>.delayed(Duration.zero);
    expect(controller.tiles, isEmpty);
  });
}

SelectedUploadFile _file(int index) => SelectedUploadFile(
  name: 'file-$index.txt',
  size: 4,
  openStream: () =>
      Stream<Uint8List>.value(Uint8List.fromList(<int>[1, 2, 3, 4])),
);

final class _Call {
  _Call(this.cancellation, this.progress);
  final RequestCancellation cancellation;
  final void Function(int, int) progress;
  final Completer<String> result = Completer<String>();
}

final class _Repository implements FileUploadRepository {
  final List<_Call> calls = <_Call>[];

  @override
  Future<String> upload({
    required String channelId,
    required SelectedUploadFile file,
    required RequestCancellation cancellation,
    required void Function(int sent, int total) onProgress,
  }) {
    final call = _Call(cancellation, onProgress);
    calls.add(call);
    return call.result.future;
  }
}
