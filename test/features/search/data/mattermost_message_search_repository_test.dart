import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/features/search/data/repositories/mattermost_message_search_repository.dart';
import 'package:mattermost_flutter/src/features/search/domain/models/message_search.dart';

import '../../../support/fake_user_repository.dart';

void main() {
  test(
    'preserves response order, replies, matches, and hydrates each channel once',
    () async {
      final _SearchApi api = _SearchApi();
      final FakeUserRepository users = FakeUserRepository();
      final MattermostMessageSearchRepository repository =
          MattermostMessageSearchRepository(
            api: api,
            users: users,
            messageMapper: const MattermostMessageMapper(),
            channelConcurrency: 2,
          );

      final MessageSearchPage page = await repository.search(
        session: _session,
        request: const MessageSearchRequest(
          teamId: 'team',
          terms: 'needle',
          timezoneOffsetSeconds: 10,
        ),
      );

      expect(
        page.results.map((MessageSearchResult item) => item.post.id),
        <String>['reply', 'root'],
      );
      expect(page.results.first.isThreadReply, isTrue);
      expect(page.results.first.matches, <String>['needle']);
      expect(api.requestedChannels, <String>['channel']);
      expect(users.requestedIdBatches.single.toSet(), <String>{'ada', 'grace'});
    },
  );

  test(
    'uses the available channel snapshot and skips orphan response ids',
    () async {
      final _SearchApi api = _SearchApi();
      final MattermostMessageSearchRepository repository =
          MattermostMessageSearchRepository(
            api: api,
            users: FakeUserRepository(),
            messageMapper: const MattermostMessageMapper(),
          );
      const SidebarChannel known = SidebarChannel(
        id: 'channel',
        teamId: 'team',
        name: 'town',
        displayName: 'Town',
        kind: ChannelKind.publicChannel,
      );

      final MessageSearchPage page = await repository.search(
        session: _session,
        request: const MessageSearchRequest(
          teamId: 'team',
          terms: 'needle',
          timezoneOffsetSeconds: 10,
        ),
        knownChannels: const <SidebarChannel>[known],
      );

      expect(page.results, hasLength(2));
      expect(page.results.first.channel, same(known));
      expect(api.requestedChannels, isEmpty);
    },
  );
}

final AuthSession _session = AuthSession(
  serverUrl: Uri(scheme: 'https', host: 'chat.example'),
  userId: 'me',
  username: 'me',
);

final class _SearchApi extends Fake implements MattermostApi {
  final List<String> requestedChannels = <String>[];

  @override
  Future<MattermostPostSearchDto> searchPosts({
    required String teamId,
    required MattermostPostSearchRequestDto request,
  }) async => MattermostPostSearchDto(
    order: const <String>['reply', 'missing', 'root'],
    posts: <String, MattermostPostDto>{
      'root': const MattermostPostDto(
        id: 'root',
        userId: 'ada',
        channelId: 'channel',
        message: 'needle root',
      ),
      'reply': const MattermostPostDto(
        id: 'reply',
        userId: 'grace',
        channelId: 'channel',
        rootId: 'root',
        message: 'needle reply',
      ),
    },
    matches: const <String, List<String>>{
      'reply': <String>['needle'],
    },
  );

  @override
  Future<MattermostChannelDto> getChannel(String channelId) async {
    requestedChannels.add(channelId);
    return const MattermostChannelDto(
      id: 'channel',
      teamId: 'team',
      type: 'O',
      name: 'town',
      displayName: 'Town',
    );
  }
}
