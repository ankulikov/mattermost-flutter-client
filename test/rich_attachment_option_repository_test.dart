import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_rich_attachment_option_repository.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment_option.dart';

void main() {
  final AuthSession session = AuthSession(
    serverUrl: Uri(scheme: 'https', host: 'chat.example.test'),
    userId: 'me',
    username: 'me',
  );

  test('maps active user search results to IDs and bounded labels', () async {
    final _Api api = _Api(
      users: const <MattermostUserDto>[
        MattermostUserDto(
          id: 'ada',
          username: 'ada',
          firstName: 'Ada',
          lastName: 'Lovelace',
        ),
        MattermostUserDto(id: 'deleted', username: 'deleted', deleteAt: 1),
      ],
    );
    final repository = MattermostRichAttachmentOptionRepository(api: api);

    final List<RichAttachmentSystemOption> result = await repository.search(
      session: session,
      dataSource: RichAttachmentSelectDataSource.users,
      query: '  ada  ',
      limit: 500,
    );

    expect(api.userTerm, 'ada');
    expect(api.userLimit, 50);
    expect(result.single.value, 'ada');
    expect(result.single.label, 'Ada Lovelace');
    expect(result.single.description, '@ada');
  });

  test('returns only active public channels with channel IDs', () async {
    final _Api api = _Api(
      channels: const <MattermostChannelDto>[
        MattermostChannelDto(
          id: 'town-square',
          teamId: 'team',
          type: 'O',
          displayName: 'Town Square',
          name: 'town-square',
        ),
        MattermostChannelDto(
          id: 'private',
          teamId: 'team',
          type: 'P',
          displayName: 'Private',
          name: 'private',
        ),
      ],
    );
    final repository = MattermostRichAttachmentOptionRepository(api: api);

    final List<RichAttachmentSystemOption> result = await repository.search(
      session: session,
      dataSource: RichAttachmentSelectDataSource.channels,
      query: 'town',
    );

    expect(api.channelTerm, 'town');
    expect(result.single.value, 'town-square');
    expect(result.single.label, 'Town Square');
    expect(result.single.description, '~town-square');
  });
}

final class _Api extends Fake implements MattermostApi {
  _Api({this.users = const [], this.channels = const []});

  final List<MattermostUserDto> users;
  final List<MattermostChannelDto> channels;
  String? userTerm;
  int? userLimit;
  String? channelTerm;

  @override
  Future<List<MattermostUserDto>> searchUsers({
    required String term,
    required int limit,
  }) async {
    userTerm = term;
    userLimit = limit;
    return users;
  }

  @override
  Future<List<MattermostChannelDto>> searchChannels({
    required String term,
    required int limit,
  }) async {
    channelTerm = term;
    return channels;
  }
}
