/// A server or session draft for one channel or thread destination.
final class Draft {
  const Draft({
    required this.channelId,
    required this.message,
    this.userId = '',
    this.rootId,
    this.fileIds = const <String>[],
    this.fileInfos = const <DraftFileInfo>[],
    this.createAt = 0,
    this.updateAt = 0,
    this.type,
    this.props,
    this.priority,
  });

  final String userId;
  final String channelId;
  final String? rootId;
  final String message;
  final List<String> fileIds;
  final List<DraftFileInfo> fileInfos;
  final int createAt;
  final int updateAt;
  final String? type;
  final Map<String, Object?>? props;
  final Map<String, Object?>? priority;
}

/// File metadata returned with a synchronized draft.
final class DraftFileInfo {
  const DraftFileInfo({
    required this.id,
    this.userId = '',
    this.channelId = '',
    this.postId = '',
    this.createAt = 0,
    this.updateAt = 0,
    this.deleteAt = 0,
    this.name = '',
    this.extension = '',
    this.size = 0,
    this.mimeType = '',
    this.width = 0,
    this.height = 0,
    this.hasPreviewImage = false,
    this.miniPreview,
    this.content = '',
    this.remoteId = '',
    this.archived = false,
  });

  final String id;
  final String userId;
  final String channelId;
  final String postId;
  final int createAt;
  final int updateAt;
  final int deleteAt;
  final String name;
  final String extension;
  final int size;
  final String mimeType;
  final int width;
  final int height;
  final bool hasPreviewImage;
  final String? miniPreview;
  final String content;
  final String remoteId;
  final bool archived;
}
