import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/file_upload/data/clipboard_file_sources_io.dart';
import 'package:path/path.dart' as p;

void main() {
  test('copied path preserves file name, extension and bytes', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'mattermost-clipboard-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final File source = File(p.join(directory.path, 'Report Final.PDF'));
    await source.writeAsBytes(<int>[0, 1, 127, 255]);

    final files = await fromPaths(<String>[source.path]);

    expect(files, hasLength(1));
    expect(files.single.name, 'Report Final.PDF');
    expect(files.single.type, 'PDF');
    expect(files.single.size, 4);
    expect(
      await files.single.openStream().expand((chunk) => chunk).toList(),
      <int>[0, 1, 127, 255],
    );
  });
}
