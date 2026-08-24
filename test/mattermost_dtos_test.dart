import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';

void main() {
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
}
