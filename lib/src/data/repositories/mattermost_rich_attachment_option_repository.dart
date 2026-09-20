import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/channel_sidebar_mapper.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment_option.dart';
import 'package:mattermost_flutter/src/domain/repositories/rich_attachment_option_repository.dart';

/// Network-only lookup for system-backed legacy attachment selects.
final class MattermostRichAttachmentOptionRepository
    implements RichAttachmentOptionRepository {
  const MattermostRichAttachmentOptionRepository({required MattermostApi api})
    : _api = api;

  static const int maxResults = 50;

  final MattermostApi _api;

  @override
  Future<List<RichAttachmentSystemOption>> search({
    required AuthSession session,
    required RichAttachmentSelectDataSource dataSource,
    required String query,
    int limit = 30,
  }) async {
    final int boundedLimit = limit.clamp(1, maxResults);
    final String term = query.trim();
    return switch (dataSource) {
      RichAttachmentSelectDataSource.users => _users(
        await _api.searchUsers(term: term, limit: boundedLimit),
        boundedLimit,
      ),
      RichAttachmentSelectDataSource.channels => _channels(
        await _api.searchChannels(term: term, limit: boundedLimit),
        boundedLimit,
      ),
      RichAttachmentSelectDataSource.unknown =>
        const <RichAttachmentSystemOption>[],
    };
  }

  static List<RichAttachmentSystemOption> _users(
    Iterable<MattermostUserDto> values,
    int limit,
  ) {
    final Set<String> seen = <String>{};
    return List<RichAttachmentSystemOption>.unmodifiable(
      values
          .where(
            (MattermostUserDto user) =>
                user.id.isNotEmpty &&
                user.username.isNotEmpty &&
                user.deleteAt == 0 &&
                seen.add(user.id),
          )
          .take(limit)
          .map(
            (MattermostUserDto user) => RichAttachmentSystemOption(
              value: user.id,
              label: userDisplayName(user),
              description: '@${user.username}',
            ),
          ),
    );
  }

  static List<RichAttachmentSystemOption> _channels(
    Iterable<MattermostChannelDto> values,
    int limit,
  ) {
    final Set<String> seen = <String>{};
    return List<RichAttachmentSystemOption>.unmodifiable(
      values
          .where(
            (MattermostChannelDto channel) =>
                channel.id.isNotEmpty &&
                channel.name.isNotEmpty &&
                channel.type == 'O' &&
                channel.deleteAt == 0 &&
                seen.add(channel.id),
          )
          .take(limit)
          .map(
            (MattermostChannelDto channel) => RichAttachmentSystemOption(
              value: channel.id,
              label: channel.displayName.trim().isEmpty
                  ? channel.name
                  : channel.displayName.trim(),
              description: '~${channel.name}',
            ),
          ),
    );
  }
}
