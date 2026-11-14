/// A server or session draft for one channel or thread destination.
final class Draft {
  const Draft({
    required this.channelId,
    required this.message,
    this.userId = '',
    this.rootId,
    this.fileIds = const <String>[],
    this.fileInfos = const <Map<String, Object?>>[],
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
  final List<Map<String, Object?>> fileInfos;
  final int createAt;
  final int updateAt;
  final String? type;
  final Map<String, Object?>? props;
  final Map<String, Object?>? priority;
}
