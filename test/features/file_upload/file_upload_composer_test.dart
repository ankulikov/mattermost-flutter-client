import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/features/file_upload/domain/file_upload.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/file_attachment_presentation.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_composer.dart';

void main() {
  test('formats upload file sizes using attachment units', () {
    expect(formatAttachmentFileSize(1023), '1023 B');
    expect(formatAttachmentFileSize(1024), '1 KB');
    expect(formatAttachmentFileSize(1024 * 1024), '1.0 MB');
    expect(formatAttachmentFileSize(1024 * 1024 * 1024), '1.0 GB');
  });

  test('selects document icons by Office extension', () {
    expect(attachmentFileIcon('doc'), Icons.description_outlined);
    expect(attachmentFileIcon('docx'), Icons.description_outlined);
    expect(attachmentFileIcon('xls'), Icons.table_chart_outlined);
    expect(attachmentFileIcon('xlsx'), Icons.table_chart_outlined);
    expect(attachmentFileIcon('ppt'), Icons.slideshow_outlined);
    expect(attachmentFileIcon('pptx'), Icons.slideshow_outlined);
  });

  test('selects image icons by common image extension', () {
    for (final String extension in <String>[
      'png',
      'jpg',
      'jpeg',
      'gif',
      'bmp',
      'webp',
      'heic',
      'heif',
      'tif',
      'tiff',
      'svg',
    ]) {
      expect(attachmentFileIcon(extension), Icons.image_outlined);
    }
  });

  for (final double width in <double>[320, 900]) {
    testWidgets(
      'attachment-only send waits for upload and retries post at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _Repository();
        final calls = <(String, List<String>)>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 800),
                  textScaler: const TextScaler.linear(1.6),
                ),
                child: MessageComposer(
                  destinationId: 'channel',
                  channelId: 'channel',
                  accountId: 'account',
                  placeholder: 'Message',
                  uploadFilePickerFactory: () => _Picker(),
                  fileUploadRepositoryFactory: () => repository,
                  onSubmit: (_, _) async {},
                  onSubmitWithFiles: (message, pendingId, ids) async {
                    calls.add((pendingId, ids));
                    if (calls.length == 1) throw StateError('post failed');
                  },
                ),
              ),
            ),
          ),
        );
        final attach = find.byKey(
          const ValueKey<String>('attach-file-channel'),
        );
        final send = find.byKey(const ValueKey<String>('send-message-channel'));
        await tester.tap(attach);
        await tester.pump();
        expect(repository.result, isNotNull);
        expect(find.text('mp3 · 3.7 MB'), findsOneWidget);
        expect(find.byIcon(Icons.audio_file_outlined), findsOneWidget);
        expect(tester.widget<IconButton>(send).onPressed, isNull);
        repository.progress?.call(4, 4);
        await tester.pump();
        expect(find.text('Finalizing upload…'), findsOneWidget);
        repository.result!.complete('file-id');
        await tester.pump();
        expect(tester.widget<IconButton>(send).onPressed, isNotNull);
        await tester.tap(send);
        await tester.pump();
        expect(find.text('Ready'), findsOneWidget);
        await tester.tap(send);
        await tester.pump();
        expect(calls, hasLength(2));
        expect(calls[0].$1, calls[1].$1);
        expect(calls[0].$2, <String>['file-id']);
        expect(repository.uploadCount, 1);
        expect(find.text('Ready'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

final class _Picker implements UploadFilePicker {
  @override
  Future<List<SelectedUploadFile>> pickFiles() async => <SelectedUploadFile>[
    SelectedUploadFile(
      name: 'episode.mp3',
      size: 3834266,
      type: 'mp3',
      openStream: () =>
          Stream<Uint8List>.value(Uint8List.fromList(<int>[1, 2, 3, 4])),
    ),
  ];
}

final class _Repository implements FileUploadRepository {
  Completer<String>? result;
  void Function(int, int)? progress;
  int uploadCount = 0;

  @override
  Future<String> upload({
    required String channelId,
    required SelectedUploadFile file,
    required RequestCancellation cancellation,
    required void Function(int sent, int total) onProgress,
  }) {
    uploadCount++;
    progress = onProgress;
    result = Completer<String>();
    return result!.future;
  }
}
