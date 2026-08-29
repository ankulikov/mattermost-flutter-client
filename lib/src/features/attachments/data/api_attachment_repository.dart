import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/attachments/domain/attachment_repository.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message.dart';

final class ApiAttachmentRepository implements AttachmentRepository {
  const ApiAttachmentRepository({
    required MattermostApi api,
    required AttachmentFileSaver fileSaver,
  }) : _api = api,
       _fileSaver = fileSaver;

  final MattermostApi _api;
  final AttachmentFileSaver _fileSaver;

  @override
  Future<AttachmentContent> load({
    required String fileId,
    required AttachmentVariant variant,
  }) async {
    final MattermostFileContentDto content = await switch (variant) {
      AttachmentVariant.thumbnail => _api.getFileThumbnail(fileId),
      AttachmentVariant.preview => _api.getFilePreview(fileId),
      AttachmentVariant.original => _api.getFile(fileId),
    };
    return AttachmentContent(
      bytes: content.bytes,
      contentType: content.contentType,
    );
  }

  @override
  Future<bool> download(PostAttachment attachment) async {
    final AttachmentContent content = await load(
      fileId: attachment.id,
      variant: AttachmentVariant.original,
    );
    return _fileSaver.save(
      bytes: content.bytes,
      fileName: attachment.name,
      mimeType: content.contentType ?? attachment.mimeType,
    );
  }
}
