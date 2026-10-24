import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/features/file_upload/domain/file_upload.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/file_attachment_presentation.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_composer.dart';

void main() {
  test('names clipboard images with local date and time', () {
    expect(
      clipboardImageName(DateTime(2026, 10, 24, 10, 20, 30), 'webp'),
      'clipboard_2026_10_24_10_20_30.webp',
    );
  });

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
    testWidgets('keyboard clipboard image uploads at $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageComposer(
              destinationId: 'channel',
              channelId: 'channel',
              accountId: 'account',
              placeholder: 'Message',
              fileUploadRepositoryFactory: () => repository,
              onSubmit: (_, _) async {},
              onSubmitWithFiles: (_, _, _) async {},
            ),
          ),
        ),
      );
      final TextField input = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('message-input-channel')),
      );
      input.contentInsertionConfiguration!.onContentInserted(
        KeyboardInsertedContent(
          mimeType: 'image/jpeg',
          uri: 'content://keyboard/image',
          data: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      );
      await tester.pump();
      expect(
        repository.lastFile?.name,
        matches(RegExp(r'^clipboard_.*\.jpg$')),
      );
      expect(repository.lastFile?.type, 'jpg');
      expect(repository.lastFile?.size, 3);
      expect(
        await repository.lastFile!
            .openStream()
            .expand((chunk) => chunk)
            .toList(),
        <int>[1, 2, 3],
      );
      repository.result!.complete('file-id');
      await tester.pump();
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });

    testWidgets('pastes a copied file at $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository();
      final clipboard = _Clipboard(<SelectedUploadFile>[
        SelectedUploadFile(
          name: 'report.pdf',
          size: 3,
          type: 'pdf',
          openStream: () =>
              Stream<Uint8List>.value(Uint8List.fromList(<int>[10, 20, 30])),
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageComposer(
              destinationId: 'channel',
              channelId: 'channel',
              accountId: 'account',
              placeholder: 'Message',
              uploadClipboardFactory: () => clipboard,
              fileUploadRepositoryFactory: () => repository,
              onSubmit: (_, _) async {},
              onSubmitWithFiles: (_, _, _) async {},
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('message-input-channel')),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(clipboard.readCount, 1);
      expect(repository.lastFile?.name, 'report.pdf');
      expect(repository.lastFile?.type, 'pdf');
      expect(
        await repository.lastFile!
            .openStream()
            .expand((chunk) => chunk)
            .toList(),
        <int>[10, 20, 30],
      );
      expect(find.text('report.pdf'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey<String>('send-message-channel')),
            )
            .onPressed,
        isNull,
      );
      repository.result!.complete('file-id');
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey<String>('send-message-channel')),
            )
            .onPressed,
        isNotNull,
      );
    });

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
        final input = find.byKey(
          const ValueKey<String>('message-input-channel'),
        );
        final fullEditor = find.byKey(
          const ValueKey<String>('open-full-editor-channel'),
        );
        final send = find.byKey(const ValueKey<String>('send-message-channel'));
        for (final Finder action in <Finder>[attach, fullEditor, send]) {
          if (width < 700) {
            expect(
              tester.getTopLeft(action).dy,
              greaterThan(tester.getBottomLeft(input).dy),
            );
          } else {
            expect(
              tester.getBottomLeft(action).dy,
              moreOrLessEquals(tester.getBottomLeft(input).dy),
            );
          }
        }
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

  testWidgets('full editor accepts Ctrl+V file paste', (tester) async {
    final repository = _Repository();
    final clipboard = _Clipboard(<SelectedUploadFile>[
      SelectedUploadFile(
        name: 'notes.txt',
        size: 2,
        type: 'txt',
        openStream: () =>
            Stream<Uint8List>.value(Uint8List.fromList(<int>[65, 66])),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageComposer(
            destinationId: 'channel',
            channelId: 'channel',
            accountId: 'account',
            placeholder: 'Message',
            uploadClipboardFactory: () => clipboard,
            fileUploadRepositoryFactory: () => repository,
            onSubmit: (_, _) async {},
            onSubmitWithFiles: (_, _, _) async {},
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('open-full-editor-channel')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('full-message-input-channel')),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(clipboard.readCount, 1);
    expect(repository.lastFile?.name, 'notes.txt');
    expect(find.text('notes.txt'), findsWidgets);
    repository.result!.complete('file-id');
    await tester.pump();
  });

  testWidgets('full editor accepts keyboard clipboard image', (tester) async {
    final repository = _Repository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageComposer(
            destinationId: 'channel',
            channelId: 'channel',
            accountId: 'account',
            placeholder: 'Message',
            fileUploadRepositoryFactory: () => repository,
            onSubmit: (_, _) async {},
            onSubmitWithFiles: (_, _, _) async {},
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('open-full-editor-channel')),
    );
    await tester.pumpAndSettle();
    final TextField input = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('full-message-input-channel')),
    );
    input.contentInsertionConfiguration!.onContentInserted(
      KeyboardInsertedContent(
        mimeType: 'image/webp',
        uri: 'content://keyboard/image',
        data: Uint8List.fromList(<int>[4, 5]),
      ),
    );
    await tester.pump();
    expect(repository.lastFile?.type, 'webp');
    expect(repository.lastFile?.name, matches(RegExp(r'^clipboard_.*\.webp$')));
    repository.result!.complete('file-id');
    await tester.pump();
  });

  testWidgets('keyboard insertion without image bytes shows an error', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageComposer(
            destinationId: 'channel',
            channelId: 'channel',
            accountId: 'account',
            placeholder: 'Message',
            fileUploadRepositoryFactory: () => repository,
            onSubmit: (_, _) async {},
          ),
        ),
      ),
    );
    final TextField input = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('message-input-channel')),
    );
    input.contentInsertionConfiguration!.onContentInserted(
      const KeyboardInsertedContent(
        mimeType: 'image/png',
        uri: 'content://keyboard/unavailable',
      ),
    );
    await tester.pump();
    expect(repository.uploadCount, 0);
    expect(find.text('Files could not be added.'), findsOneWidget);
  });

  testWidgets('plain text paste still inserts at the selection', (
    tester,
  ) async {
    final clipboard = _Clipboard(const <SelectedUploadFile>[]);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async => call.method == 'Clipboard.getData'
          ? <String, Object>{'text': 'pasted text'}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageComposer(
            destinationId: 'channel',
            channelId: 'channel',
            accountId: 'account',
            placeholder: 'Message',
            uploadClipboardFactory: () => clipboard,
            fileUploadRepositoryFactory: () => _Repository(),
            onSubmit: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('message-input-channel')),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(clipboard.readCount, 1);
    expect(find.text('pasted text'), findsOneWidget);
  });
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

final class _Clipboard implements UploadClipboard {
  _Clipboard(this.files);

  final List<SelectedUploadFile> files;
  int readCount = 0;

  @override
  Future<List<SelectedUploadFile>> readFiles() async {
    readCount++;
    return files;
  }
}

final class _Repository implements FileUploadRepository {
  Completer<String>? result;
  void Function(int, int)? progress;
  int uploadCount = 0;
  SelectedUploadFile? lastFile;

  @override
  Future<String> upload({
    required String channelId,
    required SelectedUploadFile file,
    required RequestCancellation cancellation,
    required void Function(int sent, int total) onProgress,
  }) {
    uploadCount++;
    lastFile = file;
    progress = onProgress;
    result = Completer<String>();
    return result!.future;
  }
}
