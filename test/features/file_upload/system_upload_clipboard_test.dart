import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/file_upload/data/system_upload_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('image-only clipboard content becomes a PNG upload source', () async {
    const MethodChannel channel = MethodChannel('pasteboard');
    const MethodChannel nativeChannel = MethodChannel(
      'mattermost/clipboard_files',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          nativeChannel,
          (MethodCall call) async => <Object>[],
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'files') return <String>[];
          if (call.method == 'image') return Uint8List.fromList(<int>[1, 2, 3]);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, null),
    );

    final files = await const SystemUploadClipboard().readFiles();

    expect(files, hasLength(1));
    expect(
      files.single.name,
      matches(RegExp(r'^clipboard_\d{4}(?:_\d{2}){5}\.png$')),
    );
    expect(files.single.type, 'png');
    expect(files.single.size, 3);
    expect(
      await files.single.openStream().expand((chunk) => chunk).toList(),
      <int>[1, 2, 3],
    );
  });
}
