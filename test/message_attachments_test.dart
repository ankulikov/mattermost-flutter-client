import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/repositories/attachment_repository.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_attachments.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  const PostAttachment firstImage = PostAttachment(
    id: 'image-1',
    name: 'first.png',
    size: 2048,
    mimeType: 'image/png',
    extension: 'png',
    width: 800,
    height: 600,
    hasPreviewImage: true,
  );
  const PostAttachment secondImage = PostAttachment(
    id: 'image-2',
    name: 'second.png',
    size: 4096,
    mimeType: 'image/png',
    extension: 'png',
    width: 600,
    height: 800,
    hasPreviewImage: true,
  );
  const PostAttachment document = PostAttachment(
    id: 'file-1',
    name: 'report.pdf',
    size: 8192,
    mimeType: 'application/pdf',
    extension: 'pdf',
  );

  testWidgets('shows one image as a large preview at compact and wide widths', (
    WidgetTester tester,
  ) async {
    final _FakeAttachmentRepository repository = _FakeAttachmentRepository();
    for (final double width in <double>[400, 900]) {
      await tester.binding.setSurfaceSize(Size(width, 700));
      await _pump(tester, repository, const <PostAttachment>[
        firstImage,
      ], textScaler: const TextScaler.linear(2));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('large-attachment-image-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('attachment-card-image-1')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('shows multiple files as cards and pages between images', (
    WidgetTester tester,
  ) async {
    final _FakeAttachmentRepository repository = _FakeAttachmentRepository();
    await tester.binding.setSurfaceSize(const Size(400, 700));
    await _pump(tester, repository, const <PostAttachment>[
      firstImage,
      secondImage,
      document,
    ], textScaler: const TextScaler.linear(2));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('attachment-card-image-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('attachment-card-image-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('attachment-card-file-1')),
      findsOneWidget,
    );

    await tester.tap(find.text('second.png'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('attachment-image-viewer')),
      findsOneWidget,
    );
    expect(find.text('2 of 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous image'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('first.png'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('downloads a non-image attachment when its card is pressed', (
    WidgetTester tester,
  ) async {
    final _FakeAttachmentRepository repository = _FakeAttachmentRepository();
    await _pump(tester, repository, const <PostAttachment>[document]);

    await tester.tap(find.text('report.pdf'));
    await tester.pumpAndSettle();

    expect(repository.downloaded, document);
    expect(find.text('File saved.'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  AttachmentRepository repository,
  List<PostAttachment> attachments, {
  TextScaler textScaler = TextScaler.noScaling,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [attachmentRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: MessageAttachments(attachments: attachments),
          ),
        ),
      ),
    ),
  ),
);

final class _FakeAttachmentRepository implements AttachmentRepository {
  static final Uint8List _pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
    'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  PostAttachment? downloaded;

  @override
  Future<bool> download(PostAttachment attachment) async {
    downloaded = attachment;
    return true;
  }

  @override
  Future<AttachmentContent> load({
    required String fileId,
    required AttachmentVariant variant,
  }) async => AttachmentContent(bytes: _pixel, contentType: 'image/png');
}
