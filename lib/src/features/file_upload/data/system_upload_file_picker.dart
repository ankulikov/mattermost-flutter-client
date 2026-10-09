import 'package:file_picker/file_picker.dart';
import 'package:mattermost_flutter/src/features/file_upload/domain/file_upload.dart';

final class SystemUploadFilePicker implements UploadFilePicker {
  const SystemUploadFilePicker();

  @override
  Future<List<SelectedUploadFile>> pickFiles() async {
    final files = await FilePicker.pickFiles();
    final selected = <SelectedUploadFile>[];
    for (final file in files) {
      int? size;
      try {
        size = file.lengthSync();
        size ??= await file.length();
      } on Object {
        // Keep the selected tile so it can report the unavailable source.
      }
      selected.add(
        SelectedUploadFile(
          name: file.name,
          size: size ?? -1,
          type: file.extension,
          openStream: file.readAsByteStream,
        ),
      );
    }
    return selected;
  }
}
