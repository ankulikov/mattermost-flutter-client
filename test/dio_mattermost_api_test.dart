import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/data/api/dio_mattermost_api.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';

void main() {
  test('logs out the active Mattermost session', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body: '{"status":"OK"}',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;

    await DioMattermostApi(dio: dio).logout();

    expect(adapter.request?.method, 'POST');
    expect(adapter.request?.path, '/users/logout');
  });

  test('loads users by exact usernames in one request', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body: '[{"id":"ada-id","username":"ada"}]',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    final List<MattermostUserDto> users = await api.getUsersByUsernames(
      <String>['ada'],
    );

    expect(adapter.request?.method, 'POST');
    expect(adapter.request?.path, '/users/usernames');
    expect(adapter.request?.data, '["ada"]');
    expect(users.single.id, 'ada-id');
  });

  test('searches active users with a server-side result bound', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body: '[{"id":"ada-id","username":"ada"}]',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;

    final List<MattermostUserDto> users = await DioMattermostApi(
      dio: dio,
    ).searchUsers(term: 'ada', limit: 30);

    expect(adapter.request?.path, '/users/search');
    expect(adapter.request?.data, <String, Object?>{
      'term': 'ada',
      'allow_inactive': false,
      'limit': 30,
    });
    expect(users.single.id, 'ada-id');
  });

  test('searches visible channels with paged server filtering', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '{"channels":[{"id":"town","team_id":"team","type":"O",'
          '"display_name":"Town Square","name":"town-square"}],'
          '"total_count":1}',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;

    final List<MattermostChannelDto> channels = await DioMattermostApi(
      dio: dio,
    ).searchChannels(term: 'town', limit: 30);

    expect(adapter.request?.path, '/channels/search');
    expect(adapter.request?.queryParameters, <String, Object?>{
      'system_console': true,
    });
    expect(adapter.request?.data, <String, Object?>{
      'term': 'town',
      'page': 0,
      'per_page': 30,
      'exclude_default_channels': false,
    });
    expect(channels.single.id, 'town');
  });

  test('autocompletes users with the team and channel query', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body: '{"users":[{"id":"ada-id","username":"ada"}]}',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;

    final MattermostUserAutocompleteDto result =
        await DioMattermostApi(dio: dio).autocompleteUsers(
          teamId: 'team id',
          channelId: 'channel id',
          name: 'ada',
          limit: 20,
        );

    expect(adapter.request?.method, 'GET');
    expect(adapter.request?.path, '/users/autocomplete');
    expect(adapter.request?.queryParameters, <String, dynamic>{
      'in_team': 'team id',
      'in_channel': 'channel id',
      'name': 'ada',
      'limit': 20,
    });
    expect(result.users.single.id, 'ada-id');
  });

  test(
    'searches team posts with the exact privacy-safe request body',
    () async {
      final _RecordingAdapter adapter = _RecordingAdapter(
        body:
            '{"order":["post-1","missing"],"posts":{"post-1":'
            '{"id":"post-1","user_id":"ada","channel_id":"town",'
            '"message":"confidential"}},"matches":{"post-1":'
            '["confidential"]}}',
      );
      final Dio dio = Dio(
        BaseOptions(baseUrl: 'https://chat.example.com/api/v4'),
      )..httpClientAdapter = adapter;

      final MattermostPostSearchDto result = await DioMattermostApi(dio: dio)
          .searchPosts(
            teamId: 'team id',
            request: const MattermostPostSearchRequestDto(
              terms: 'confidential from:ada',
              timezoneOffset: 10800,
              page: 2,
              perPage: 60,
            ),
          );

      expect(adapter.request?.method, 'POST');
      expect(adapter.request?.path, '/teams/team%20id/posts/search');
      expect(adapter.request?.data, <String, Object?>{
        'terms': 'confidential from:ada',
        'is_or_search': false,
        'time_zone_offset': 10800,
        'include_deleted_channels': false,
        'page': 2,
        'per_page': 60,
      });
      expect(result.order, <String>['post-1', 'missing']);
      expect(result.posts['post-1']?.id, 'post-1');
      expect(result.matches['post-1'], <String>['confidential']);
    },
  );

  test('tolerates absent search matches and unknown fields', () {
    final MattermostPostSearchDto result = MattermostPostSearchDto.fromJson(
      <String, Object?>{
        'order': <Object?>['orphan'],
        'posts': <String, Object?>{},
        'matches': null,
        'unknown': true,
      },
    );

    expect(result.order, <String>['orphan']);
    expect(result.posts, isEmpty);
    expect(result.matches, isEmpty);
  });

  test('autocompletes team channels for message search', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '[{"id":"town","team_id":"team","type":"O",'
          '"display_name":"Town Square","name":"town-square"}]',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;

    final List<MattermostChannelDto> channels = await DioMattermostApi(
      dio: dio,
    ).autocompleteChannelsForSearch(teamId: 'team id', name: 'town square');

    expect(adapter.request?.method, 'GET');
    expect(
      adapter.request?.path,
      '/teams/team%20id/channels/search_autocomplete',
    );
    expect(adapter.request?.queryParameters, <String, Object?>{
      'name': 'town square',
    });
    expect(channels.single.name, 'town-square');
  });

  test('searches referenceable groups with member counts', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '[{"id":"group-1","name":"backend",'
          '"display_name":"Backend Team","allow_reference":true,'
          '"member_count":18}]',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;

    final List<MattermostGroupDto> groups = await DioMattermostApi(
      dio: dio,
    ).searchMentionGroups(name: 'back', limit: 25);

    expect(adapter.request?.method, 'GET');
    expect(adapter.request?.path, '/groups');
    expect(adapter.request?.queryParameters, <String, dynamic>{
      'q': 'back',
      'filter_allow_reference': true,
      'page': 0,
      'per_page': 25,
      'include_member_count': true,
    });
    expect(groups.single.memberCount, 18);
  });

  test('resolves exact group names in one request', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '[{"id":"group-1","name":"backend",'
          '"display_name":"Backend Team","allow_reference":true}]',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;

    final List<MattermostGroupDto> groups = await DioMattermostApi(
      dio: dio,
    ).getGroupsByNames(<String>['backend']);

    expect(adapter.request?.method, 'POST');
    expect(adapter.request?.path, '/groups/names');
    expect(adapter.request?.data, '["backend"]');
    expect(groups.single.name, 'backend');
  });

  test('loads the current user group memberships', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '[{"id":"group-1","name":"backend",'
          '"display_name":"Backend Team","allow_reference":true}]',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;

    final List<MattermostGroupDto> groups = await DioMattermostApi(
      dio: dio,
    ).getGroupsForUser('user id');

    expect(adapter.request?.method, 'GET');
    expect(adapter.request?.path, '/users/user%20id/groups');
    expect(groups.single.name, 'backend');
  });

  test('loads a fresh complete user profile by id', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '{"id":"ada","username":"ada","position":"Engineer",'
          '"email":"ada@example.com"}',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    final MattermostUserDto user = await api.getUserById('ada');

    expect(adapter.request?.method, 'GET');
    expect(adapter.request?.path, '/users/ada');
    expect(user.position, 'Engineer');
    expect(user.email, 'ada@example.com');
  });

  test('loads user status by id', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body: '{"user_id":"ada","status":"online","manual":false}',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    final MattermostUserStatusDto status = await api.getUserStatus('ada');

    expect(adapter.request?.path, '/users/ada/status');
    expect(status.userId, 'ada');
    expect(status.status, 'online');
  });

  test('loads permalink post and channel details', () async {
    final _RecordingAdapter postAdapter = _RecordingAdapter(
      body:
          '{"id":"post%2B1","user_id":"ada",'
          '"channel_id":"channel+1","message":"linked"}',
    );
    final Dio postDio = Dio(
      BaseOptions(baseUrl: 'https://chat.example.com/api/v4'),
    )..httpClientAdapter = postAdapter;
    await DioMattermostApi(dio: postDio).getPost('post+1');
    expect(postAdapter.request?.path, '/posts/post%2B1');

    final _RecordingAdapter channelAdapter = _RecordingAdapter(
      body:
          '{"id":"channel+1","team_id":"team-1","type":"O",'
          '"display_name":"Town Square","name":"town-square"}',
    );
    final Dio channelDio = Dio(
      BaseOptions(baseUrl: 'https://chat.example.com/api/v4'),
    )..httpClientAdapter = channelAdapter;
    await DioMattermostApi(dio: channelDio).getChannel('channel+1');
    expect(channelAdapter.request?.path, '/channels/channel%2B1');
  });

  test('loads posts after the historical channel cursor', () async {
    final _RecordingAdapter adapter = _RecordingAdapter();
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;

    await DioMattermostApi(
      dio: dio,
    ).getPostsAfter(channelId: 'channel+1', postId: 'post-1', perPage: 30);

    expect(adapter.request?.path, '/channels/channel%2B1/posts');
    expect(adapter.request?.queryParameters, <String, Object?>{
      'after': 'post-1',
      'page': 0,
      'per_page': 30,
    });
  });

  test('updates a timed user status in epoch seconds', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '{"user_id":"ada","status":"dnd","manual":true,'
          '"dnd_end_time":1789057800}',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    final MattermostUserStatusDto status = await api.updateUserStatus(
      userId: 'ada',
      status: 'dnd',
      dndEndTime: 1789057800,
    );

    expect(adapter.request?.method, 'PUT');
    expect(adapter.request?.path, '/users/ada/status');
    expect(adapter.request?.data, <String, Object?>{
      'user_id': 'ada',
      'status': 'dnd',
      'dnd_end_time': 1789057800,
    });
    expect(status.dndEndTime, 1789057800);
  });

  test('sets and clears a custom user status', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(body: '{}');
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);
    final DateTime expiresAt = DateTime.utc(2026, 9, 10, 15, 30);

    await api.updateUserCustomStatus(
      userId: 'ada',
      status: MattermostCustomStatusRequestDto(
        emoji: 'calendar',
        text: 'In a meeting',
        duration: 'one_hour',
        expiresAt: expiresAt,
      ),
    );

    expect(adapter.request?.method, 'PUT');
    expect(adapter.request?.path, '/users/ada/status/custom');
    expect(adapter.request?.data, <String, Object?>{
      'emoji': 'calendar',
      'text': 'In a meeting',
      'duration': 'one_hour',
      'expires_at': '2026-09-10T15:30:00.000Z',
    });

    await api.removeUserCustomStatus('ada');
    expect(adapter.request?.method, 'DELETE');
    expect(adapter.request?.path, '/users/ada/status/custom');
  });

  test('creates a direct channel for exactly two users', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '{"id":"dm-1","team_id":"","type":"D",'
          '"display_name":"","name":"ada__me"}',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    final MattermostChannelDto channel = await api.createDirectChannel(
      currentUserId: 'me',
      otherUserId: 'ada',
    );

    expect(adapter.request?.method, 'POST');
    expect(adapter.request?.path, '/channels/direct');
    expect(adapter.request?.data, '["me","ada"]');
    expect(channel.id, 'dm-1');
  });

  test('creates a text post with reply and pending identifiers', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '{"id":"post-1","user_id":"me","channel_id":"channel-1",'
          '"root_id":"root-1","message":"Hello","pending_post_id":"pending-1"}',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    final MattermostPostDto created = await api.createPost(
      const MattermostCreatePostRequestDto(
        channelId: 'channel-1',
        message: 'Hello',
        rootId: 'root-1',
        pendingPostId: 'pending-1',
      ),
    );

    expect(adapter.request?.method, 'POST');
    expect(adapter.request?.path, '/posts');
    expect(adapter.request?.data, <String, Object?>{
      'channel_id': 'channel-1',
      'message': 'Hello',
      'pending_post_id': 'pending-1',
      'root_id': 'root-1',
    });
    expect(created.id, 'post-1');
    expect(created.rootId, 'root-1');
  });

  test('deletes a post with an encoded identifier', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(body: '{}');
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    await api.deletePost('post / one');

    expect(adapter.request?.method, 'DELETE');
    expect(adapter.request?.path, '/posts/post%20%2F%20one');
  });

  test(
    'dispatches an attachment action with encoded IDs and selection',
    () async {
      final _RecordingAdapter adapter = _RecordingAdapter(
        body:
            '{"status":"OK","trigger_id":"trigger-1","goto_location":"/team/pl/post-2"}',
      );
      final DioMattermostApi api = DioMattermostApi(
        dio: Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
          ..httpClientAdapter = adapter,
      );

      final MattermostPostActionResponseDto result = await api
          .executePostAction(
            postId: 'post / one',
            actionId: 'select/action',
            request: const MattermostPostActionRequestDto(
              cookie: 'opaque',
              selectedOption: 'ada',
            ),
          );

      expect(adapter.request?.method, 'POST');
      expect(
        adapter.request?.path,
        '/posts/post%20%2F%20one/actions/select%2Faction',
      );
      expect(adapter.request?.data, <String, Object?>{
        'cookie': 'opaque',
        'selected_option': 'ada',
      });
      expect(result.triggerId, 'trigger-1');
      expect(result.gotoLocation, '/team/pl/post-2');
    },
  );

  test('surfaces a failed attachment action response', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body: '{"message":"Action denied"}',
      statusCode: 403,
    );
    final DioMattermostApi api = DioMattermostApi(
      dio: Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
        ..httpClientAdapter = adapter,
    );

    await expectLater(
      api.executePostAction(
        postId: 'post-1',
        actionId: 'approve',
        request: const MattermostPostActionRequestDto(cookie: 'opaque'),
      ),
      throwsA(isA<DioException>()),
    );
  });

  test('creates and removes an encoded emoji reaction', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(body: '{}');
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    await api.saveReaction(
      userId: 'me',
      postId: 'post-1',
      emojiName: 'party+parrot',
    );

    expect(adapter.request?.method, 'POST');
    expect(adapter.request?.path, '/reactions');
    expect(adapter.request?.data, <String, Object?>{
      'user_id': 'me',
      'post_id': 'post-1',
      'emoji_name': 'party+parrot',
    });

    await api.deleteReaction(
      userId: 'me',
      postId: 'post-1',
      emojiName: 'party+parrot',
    );

    expect(adapter.request?.method, 'DELETE');
    expect(
      adapter.request?.path,
      '/users/me/posts/post-1/reactions/party%2Bparrot',
    );
  });

  test('downloads a versioned authenticated profile image as bytes', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      contentType: 'image/png',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    final MattermostImageDto image = await api.getUserProfileImage(
      userId: 'user-1',
      lastPictureUpdate: 1234,
    );

    expect(adapter.request?.path, '/users/user-1/image');
    expect(adapter.request?.queryParameters, <String, Object?>{'_': 1234});
    expect(adapter.request?.headers['Accept'], 'image/*');
    expect(adapter.request?.responseType, ResponseType.bytes);
    expect(image.bytes, <int>[1, 2, 3]);
    expect(image.contentType, 'image/png');
  });

  test('resolves custom emoji metadata by encoded name', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '{"id":"emoji-1","creator_id":"ada","name":"party+parrot",'
          '"create_at":1,"update_at":2,"delete_at":0}',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;

    final MattermostEmojiDto emoji = await DioMattermostApi(
      dio: dio,
    ).getCustomEmojiByName('party+parrot');

    expect(adapter.request?.method, 'GET');
    expect(adapter.request?.path, '/emoji/name/party%2Bparrot');
    expect(emoji.id, 'emoji-1');
  });

  test(
    'lists and searches custom emoji with the documented contract',
    () async {
      final _RecordingAdapter adapter = _RecordingAdapter(
        body:
            '[{"id":"emoji-1","creator_id":"ada","name":"party_parrot",'
            '"create_at":1,"update_at":2,"delete_at":0}]',
      );
      final Dio dio = Dio(
        BaseOptions(baseUrl: 'https://chat.example.com/api/v4'),
      )..httpClientAdapter = adapter;
      final DioMattermostApi api = DioMattermostApi(dio: dio);

      final List<MattermostEmojiDto> page = await api.getCustomEmojis(page: 2);
      expect(adapter.request?.method, 'GET');
      expect(adapter.request?.path, '/emoji');
      expect(adapter.request?.queryParameters, <String, Object?>{
        'page': 2,
        'per_page': 90,
        'sort': 'name',
      });
      expect(page.single.name, 'party_parrot');

      final List<MattermostEmojiDto> search = await api.searchCustomEmojis(
        'party',
      );
      expect(adapter.request?.method, 'POST');
      expect(adapter.request?.path, '/emoji/search');
      expect(adapter.request?.data, <String, Object?>{'term': 'party'});
      expect(search.single.id, 'emoji-1');
    },
  );

  test('downloads an authenticated custom emoji image', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      bytes: Uint8List.fromList(<int>[4, 5, 6]),
      contentType: 'image/gif',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;

    final MattermostImageDto image = await DioMattermostApi(
      dio: dio,
    ).getCustomEmojiImage('emoji-1');

    expect(adapter.request?.path, '/emoji/emoji-1/image');
    expect(adapter.request?.headers['Accept'], 'image/*');
    expect(adapter.request?.responseType, ResponseType.bytes);
    expect(image.bytes, <int>[4, 5, 6]);
    expect(image.contentType, 'image/gif');
  });

  test('downloads authenticated file variants as bytes', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      bytes: Uint8List.fromList(<int>[7, 8, 9]),
      contentType: 'image/png',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    final MattermostFileContentDto thumbnail = await api.getFileThumbnail(
      'file+1',
    );
    expect(adapter.request?.path, '/files/file%2B1/thumbnail');
    expect(adapter.request?.responseType, ResponseType.bytes);
    expect(thumbnail.bytes, <int>[7, 8, 9]);

    await api.getFilePreview('file+1');
    expect(adapter.request?.path, '/files/file%2B1/preview');

    final MattermostFileContentDto original = await api.getFile('file+1');
    expect(adapter.request?.path, '/files/file%2B1');
    expect(original.contentType, 'image/png');
  });

  test('sends the complete cursor for upward thread pagination', () async {
    final _RecordingAdapter adapter = _RecordingAdapter();
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    await api.getPostThread(
      rootPostId: 'root-1',
      perPage: 60,
      fromPost: 'reply-59',
      fromCreateAt: 2059,
      direction: PostThreadDirection.up,
    );

    expect(adapter.request?.path, '/posts/root-1/thread');
    expect(adapter.request?.queryParameters, <String, Object?>{
      'perPage': 60,
      'direction': 'up',
      'fromPost': 'reply-59',
      'fromCreateAt': 2059,
    });
  });

  test('requests an extended followed-threads page with a cursor', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '{"total":0,"total_unread_threads":0,'
          '"total_unread_mentions":0,"threads":[]}',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    await api.getUserThreads(
      userId: 'me',
      teamId: 'team-1',
      before: 'root-200',
    );

    expect(adapter.request?.path, '/users/me/teams/team-1/threads');
    expect(adapter.request?.queryParameters, <String, Object?>{
      'per_page': 60,
      'extended': true,
      'before': 'root-200',
    });
  });

  test('marks a followed thread read at the supplied timestamp', () async {
    final _RecordingAdapter adapter = _RecordingAdapter();
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    await api.updateThreadRead(
      userId: 'me',
      teamId: 'team-1',
      threadId: 'root-1',
      timestamp: 123456,
    );

    expect(adapter.request?.method, 'PUT');
    expect(
      adapter.request?.path,
      '/users/me/teams/team-1/threads/root-1/read/123456',
    );
  });

  test('loads team channel memberships with Inbox counters', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '[{"channel_id":"channel-1","user_id":"me",'
          '"last_viewed_at":100,"msg_count":4,"msg_count_root":3,'
          '"mention_count":2,"mention_count_root":1,'
          '"notify_props":{"desktop":"all","mark_unread":"all"}}]',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;

    final List<MattermostChannelMemberDto> members = await DioMattermostApi(
      dio: dio,
    ).getChannelMembersForUser(userId: 'me', teamId: 'team-1');

    expect(adapter.request?.method, 'GET');
    expect(adapter.request?.path, '/users/me/teams/team-1/channels/members');
    expect(members.single.msgCountRoot, 3);
    expect(members.single.mentionCountRoot, 1);
    expect(members.single.notifyProps?.desktop, 'all');
  });

  test('loads the bounded posts around a channel unread boundary', () async {
    final _RecordingAdapter adapter = _RecordingAdapter();
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;

    await DioMattermostApi(dio: dio).getUnreadPostsForChannel(
      userId: 'me',
      channelId: 'channel-1',
      limitBefore: 20,
      limitAfter: 200,
    );

    expect(adapter.request?.method, 'GET');
    expect(adapter.request?.path, '/users/me/channels/channel-1/posts/unread');
    expect(adapter.request?.queryParameters, <String, Object?>{
      'limit_before': 20,
      'limit_after': 200,
    });
  });

  test('hydrates postponed posts by IDs in one request', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '[{"id":"post-1","user_id":"ada","channel_id":"dm-1",'
          '"message":"Later"}]',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;

    final List<MattermostPostDto> posts = await DioMattermostApi(
      dio: dio,
    ).getPostsByIds(<String>['post-1']);

    expect(adapter.request?.method, 'POST');
    expect(adapter.request?.path, '/posts/ids');
    expect(adapter.request?.data, '["post-1"]');
    expect(posts.single.message, 'Later');
  });

  test('reads, upserts, and deletes postponed preferences', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      body:
          '[{"user_id":"me","category":"postponed_messages",'
          '"name":"post-1","value":"1"}]',
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);
    const MattermostPreferenceDto preference = MattermostPreferenceDto(
      userId: 'me',
      category: 'postponed_messages',
      name: 'post-1',
      value: '1',
    );

    final List<MattermostPreferenceDto> preferences = await api
        .getPreferencesByCategory(userId: 'me', category: 'postponed_messages');
    expect(adapter.request?.method, 'GET');
    expect(adapter.request?.path, '/users/me/preferences/postponed_messages');
    expect(preferences.single.name, 'post-1');

    await api.savePreferences(
      userId: 'me',
      preferences: <MattermostPreferenceDto>[preference],
    );
    expect(adapter.request?.method, 'PUT');
    expect(adapter.request?.path, '/users/me/preferences');
    expect(adapter.request?.data, <Map<String, Object?>>[preference.toJson()]);

    await api.deletePreferences(
      userId: 'me',
      preferences: <MattermostPreferenceDto>[preference],
    );
    expect(adapter.request?.method, 'POST');
    expect(adapter.request?.path, '/users/me/preferences/delete');
    expect(adapter.request?.data, <Map<String, Object?>>[preference.toJson()]);
  });

  test('views a channel and changes CRT following state', () async {
    final _RecordingAdapter adapter = _RecordingAdapter();
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com/api/v4'))
      ..httpClientAdapter = adapter;
    final DioMattermostApi api = DioMattermostApi(dio: dio);

    await api.viewChannel(
      userId: 'me',
      channelId: 'channel-1',
      previousChannelId: 'channel-0',
    );
    expect(adapter.request?.method, 'POST');
    expect(adapter.request?.path, '/channels/members/me/view');
    expect(adapter.request?.data, <String, Object?>{
      'channel_id': 'channel-1',
      'prev_channel_id': 'channel-0',
    });

    await api.followThread(userId: 'me', teamId: 'team-1', threadId: 'root-1');
    expect(adapter.request?.method, 'PUT');
    expect(
      adapter.request?.path,
      '/users/me/teams/team-1/threads/root-1/following',
    );

    await api.unfollowThread(
      userId: 'me',
      teamId: 'team-1',
      threadId: 'root-1',
    );
    expect(adapter.request?.method, 'DELETE');
    expect(
      adapter.request?.path,
      '/users/me/teams/team-1/threads/root-1/following',
    );
  });

  test(
    'cancels an in-flight Dio request from its presentation scope',
    () async {
      final _CancellableAdapter adapter = _CancellableAdapter();
      final Dio dio = Dio(
        BaseOptions(baseUrl: 'https://chat.example.com/api/v4'),
      )..httpClientAdapter = adapter;
      final DioMattermostApi api = DioMattermostApi(dio: dio);
      final RequestCancellation cancellation = RequestCancellation();

      final Future<MattermostUserDto> request = cancellation.run(
        api.getCurrentUser,
      );
      await adapter.started.future;
      cancellation.cancel('screen disposed');

      await expectLater(
        request,
        throwsA(
          isA<DioException>().having(
            (DioException error) => error.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      expect(adapter.cancelled, isTrue);
    },
  );
}

final class _CancellableAdapter implements HttpClientAdapter {
  final Completer<void> started = Completer<void>();
  bool cancelled = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    started.complete();
    await cancelFuture;
    cancelled = true;
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

final class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({
    this.body =
        '{"order":[],"posts":{},"next_post_id":"",'
        '"prev_post_id":"","has_next":false}',
    this.bytes,
    this.contentType = 'application/json',
    this.statusCode = 200,
  });

  final String body;
  final Uint8List? bytes;
  final String contentType;
  final int statusCode;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody(
      bytes == null
          ? Stream<Uint8List>.value(Uint8List.fromList(body.codeUnits))
          : Stream<Uint8List>.value(bytes!),
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
