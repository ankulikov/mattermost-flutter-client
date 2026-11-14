import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';

/// Wire representation of a Mattermost draft.
///
/// Extension-owned properties and priority options retain their JSON objects
/// because their contents can vary between server versions.
final class MattermostDraftDto {
  const MattermostDraftDto({
    required this.channelId,
    required this.message,
    this.userId = '',
    this.rootId,
    this.fileIds = const <String>[],
    this.fileInfos = const <MattermostFileInfoDto>[],
    this.createAt = 0,
    this.updateAt = 0,
    this.type,
    this.props,
    this.priority,
  });

  factory MattermostDraftDto.fromJson(Map<String, Object?> json) =>
      MattermostDraftDto(
        channelId: json['channel_id'] as String,
        message: json['message'] as String? ?? '',
        userId: json['user_id'] as String? ?? '',
        rootId: json['root_id'] as String?,
        fileIds: (json['file_ids'] as List<Object?>? ?? const <Object?>[])
            .cast<String>(),
        fileInfos: _parseFiles(json),
        createAt: (json['create_at'] as num?)?.toInt() ?? 0,
        updateAt: (json['update_at'] as num?)?.toInt() ?? 0,
        type: json['type'] as String?,
        props: json['props'] as Map<String, Object?>?,
        priority: json['priority'] as Map<String, Object?>?,
      );

  final String channelId;
  final String message;
  final String userId;
  final String? rootId;
  final List<String> fileIds;
  final List<MattermostFileInfoDto> fileInfos;
  final int createAt;
  final int updateAt;
  final String? type;
  final Map<String, Object?>? props;
  final Map<String, Object?>? priority;

  /// The upsert endpoint derives ownership and timestamps on the server.
  Map<String, Object?> toJson() => <String, Object?>{
    'channel_id': channelId,
    'message': message,
    if (rootId != null && rootId!.isNotEmpty) 'root_id': rootId,
    if (fileIds.isNotEmpty) 'file_ids': fileIds,
    if (type != null) 'type': type,
    if (props != null) 'props': props,
    if (priority != null) 'priority': priority,
  };
}

List<MattermostFileInfoDto> _parseFiles(Map<String, Object?> json) {
  final metadata = json['metadata'];
  final files = metadata is Map<String, Object?> ? metadata['files'] : null;
  final values = files is List<Object?> ? files : json['file_infos'];
  if (values is! List<Object?>) return const [];
  return values
      .whereType<Map<String, Object?>>()
      .map(MattermostFileInfoDto.fromJson)
      .toList(growable: false);
}
