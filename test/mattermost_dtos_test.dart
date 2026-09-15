import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';

void main() {
  test('parses autocomplete users and leaves optional sections absent', () {
    final MattermostUserAutocompleteDto result =
        MattermostUserAutocompleteDto.fromJson(<String, Object?>{
          'users': <Object?>[
            <String, Object?>{'id': 'ada-id', 'username': 'ada'},
          ],
        });

    expect(result.users.single.username, 'ada');
    expect(result.outOfChannel, isNull);
    expect(result.agents, isNull);
  });

  test('decodes profile picture versions for people and bots', () {
    final MattermostUserDto person = MattermostUserDto.fromJson(
      <String, Object?>{
        'id': 'person-1',
        'username': 'person',
        'last_picture_update': 123,
      },
    );
    final MattermostUserDto bot = MattermostUserDto.fromJson(<String, Object?>{
      'id': 'bot-1',
      'username': 'bot',
      'is_bot': true,
      'last_picture_update': 123,
      'bot_last_icon_update': 456,
    });

    expect(person.profileImageUpdatedAt, 123);
    expect(bot.profileImageUpdatedAt, 456);
  });

  test('decodes channel categories with their separate order', () {
    final MattermostChannelCategoriesDto result =
        MattermostChannelCategoriesDto.fromJson(<String, Object?>{
          'categories': <Object?>[
            <String, Object?>{
              'id': 'category-1',
              'user_id': 'user-1',
              'team_id': 'team-1',
              'sort_order': 10,
              'sorting': 'recent',
              'type': 'custom',
              'display_name': 'AI',
              'muted': false,
              'collapsed': false,
              'channel_ids': <Object?>['channel-1'],
            },
          ],
          'order': <Object?>['category-2', 'category-1'],
        });

    expect(result.order, <String>['category-2', 'category-1']);
    expect(result.categories.single.id, 'category-1');
    expect(result.categories.single.sortOrder, 10);
    expect(result.categories.single.sorting, 'recent');
    expect(result.categories.single.muted, isFalse);
    expect(result.categories.single.collapsed, isFalse);
  });

  test('decodes the complete post-list response into typed DTOs', () {
    final MattermostPostListDto result = MattermostPostListDto.fromJson(
      <String, Object?>{
        'order': <Object?>['post-1'],
        'posts': <String, Object?>{
          'post-1': <String, Object?>{
            'id': 'post-1',
            'user_id': 'user-1',
            'channel_id': 'channel-1',
            'message': 'Hello',
            'root_id': '',
            'reply_count': 3,
            'last_reply_at': 99,
            'props': <String, Object?>{
              'attachments': <Object?>[
                <String, Object?>{'title': 'Typed extension data'},
              ],
            },
            'metadata': <String, Object?>{
              'images': <String, Object?>{
                'https://example.com/image.png': <String, Object?>{
                  'height': 200,
                  'width': 320,
                },
              },
              'reactions': <Object?>[
                <String, Object?>{
                  'user_id': 'user-2',
                  'post_id': 'post-1',
                  'emoji_name': 'thumbsup',
                  'create_at': 42,
                },
              ],
            },
          },
        },
        'next_post_id': 'post-2',
        'prev_post_id': '',
        'has_next': true,
      },
    );

    final MattermostPostDto post = result.posts['post-1']!;
    expect(result.order, <String>['post-1']);
    expect(result.nextPostId, 'post-2');
    expect(result.hasNext, isTrue);
    expect(post.message, 'Hello');
    expect(post.replyCount, 3);
    expect(post.lastReplyAt, 99);
    expect(post.metadata!.images['https://example.com/image.png']!.width, 320);
    expect(post.metadata!.reactions.single.emojiName, 'thumbsup');
    expect(post.props!.values['attachments'], isA<JsonArrayDto>());
  });

  test('rejects a structurally invalid typed field', () {
    expect(
      () => MattermostChannelDto.fromJson(<String, Object?>{
        'id': 'channel-1',
        'team_id': 'team-1',
        'type': 'O',
        'display_name': 'Town Square',
        'name': 'town-square',
        'total_msg_count': 'not-an-integer',
      }),
      throwsFormatException,
    );
  });

  test('decodes followed thread unread counts and extended participants', () {
    final MattermostUserThreadsDto result = MattermostUserThreadsDto.fromJson(
      <String, Object?>{
        'total': 4,
        'total_unread_threads': 2,
        'total_unread_mentions': 3,
        'threads': <Object?>[
          <String, Object?>{
            'id': 'root-1',
            'reply_count': 5,
            'last_reply_at': 2000,
            'last_viewed_at': 1500,
            'unread_replies': 2,
            'unread_mentions': 1,
            'participants': <Object?>[
              <String, Object?>{'id': 'ada', 'username': 'ada'},
            ],
            'post': <String, Object?>{
              'id': 'root-1',
              'user_id': 'ada',
              'channel_id': 'town-square',
              'message': 'Root',
            },
          },
        ],
      },
    );

    expect(result.total, 4);
    expect(result.totalUnreadThreads, 2);
    expect(result.totalUnreadMentions, 3);
    expect(result.threads.single.unreadReplies, 2);
    expect(result.threads.single.unreadMentions, 1);
    expect(result.threads.single.participants.single.username, 'ada');
    expect(result.threads.single.post!.message, 'Root');
  });

  test(
    'decodes Inbox membership, notification, preference and root counters',
    () {
      final MattermostChannelDto channel =
          MattermostChannelDto.fromJson(<String, Object?>{
            'id': 'channel-1',
            'team_id': 'team-1',
            'type': 'O',
            'display_name': 'Town Square',
            'name': 'town-square',
            'total_msg_count': 10,
            'total_msg_count_root': 7,
          });
      final MattermostChannelMemberDto member =
          MattermostChannelMemberDto.fromJson(<String, Object?>{
            'channel_id': 'channel-1',
            'user_id': 'me',
            'msg_count': 4,
            'msg_count_root': 3,
            'mention_count': 2,
            'mention_count_root': 1,
            'notify_props': <String, Object?>{
              'desktop': 'all',
              'push': 'default',
              'mark_unread': 'all',
              'ignore_channel_mentions': 'off',
              'channel_auto_follow_threads': 'on',
            },
          });
      final MattermostPreferenceDto preference =
          MattermostPreferenceDto.fromJson(<String, Object?>{
            'user_id': 'me',
            'category': 'postponed_messages',
            'name': 'post-1',
            'value': '1',
          });

      expect(channel.totalMessageCountRoot, 7);
      expect(member.msgCountRoot, 3);
      expect(member.mentionCountRoot, 1);
      expect(member.notifyProps?.channelAutoFollowThreads, 'on');
      expect(preference.toJson()['category'], 'postponed_messages');
    },
  );
}
