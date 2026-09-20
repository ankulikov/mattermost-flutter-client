import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/mappers/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';

void main() {
  test('uses the Mattermost system dictionary for reaction labels', () {
    const MattermostPostDto post = MattermostPostDto(
      id: 'post-1',
      userId: 'ada',
      channelId: 'channel-1',
      message: '',
      metadata: MattermostPostMetadataDto(
        reactions: <MattermostReactionDto>[
          MattermostReactionDto(
            userId: 'ada',
            postId: 'post-1',
            emojiName: 'large_green_circle',
            createAt: 1,
          ),
        ],
      ),
    );

    final ChannelPost mapped = const MattermostMessageMapper()
        .map(
          posts: const <MattermostPostDto>[post],
          users: const <UserSummary>[],
          currentUserId: 'ada',
        )
        .single;

    expect(mapped.reactions.single.emoji, '🟢');
    expect(mapped.reactions.single.emojiName, 'large_green_circle');
    expect(mapped.reactions.single.reactedByCurrentUser, isTrue);
  });

  test('carries active custom emoji metadata into the message snapshot', () {
    const MattermostPostDto post = MattermostPostDto(
      id: 'post-1',
      userId: 'ada',
      channelId: 'channel-1',
      message: 'Hello :party_parrot:',
      metadata: MattermostPostMetadataDto(
        emojis: <MattermostEmojiDto>[
          MattermostEmojiDto(
            id: 'emoji-1',
            creatorId: 'ada',
            name: 'party_parrot',
            createAt: 1,
            updateAt: 42,
            deleteAt: 0,
          ),
          MattermostEmojiDto(
            id: 'deleted',
            creatorId: 'ada',
            name: 'old_emoji',
            createAt: 1,
            updateAt: 2,
            deleteAt: 3,
          ),
        ],
      ),
    );

    final ChannelPost mapped = const MattermostMessageMapper()
        .map(
          posts: const <MattermostPostDto>[post],
          users: const <UserSummary>[
            UserSummary(
              id: 'ada',
              username: 'ada',
              firstName: '',
              lastName: '',
              nickname: '',
              position: '',
              email: '',
            ),
          ],
          currentUserId: 'ada',
        )
        .single;

    expect(mapped.customEmojis, hasLength(1));
    expect(mapped.customEmojis.single.name, 'party_parrot');
    expect(mapped.customEmojis.single.id, 'emoji-1');
    expect(mapped.customEmojis.single.updatedAt, 42);
  });

  test('carries active file metadata into the message snapshot', () {
    const MattermostPostDto post = MattermostPostDto(
      id: 'post-1',
      userId: 'ada',
      channelId: 'channel-1',
      message: 'See attachment',
      metadata: MattermostPostMetadataDto(
        files: <MattermostFileInfoDto>[
          MattermostFileInfoDto(
            id: 'image-1',
            userId: 'ada',
            postId: 'post-1',
            createAt: 1,
            updateAt: 1,
            deleteAt: 0,
            name: 'photo.png',
            extension: 'png',
            size: 2048,
            mimeType: 'image/png',
            width: 800,
            height: 600,
            hasPreviewImage: true,
            miniPreview: null,
            content: '',
            remoteId: '',
            archived: false,
          ),
          MattermostFileInfoDto(
            id: 'deleted-file',
            userId: 'ada',
            postId: 'post-1',
            createAt: 1,
            updateAt: 2,
            deleteAt: 3,
            name: 'old.txt',
            extension: 'txt',
            size: 10,
            mimeType: 'text/plain',
            width: 0,
            height: 0,
            hasPreviewImage: false,
            miniPreview: null,
            content: '',
            remoteId: '',
            archived: false,
          ),
        ],
      ),
    );

    final ChannelPost mapped = const MattermostMessageMapper()
        .map(
          posts: const <MattermostPostDto>[post],
          users: const <UserSummary>[
            UserSummary(
              id: 'ada',
              username: 'ada',
              firstName: '',
              lastName: '',
              nickname: '',
              position: '',
              email: '',
            ),
          ],
          currentUserId: 'ada',
        )
        .single;

    expect(mapped.attachments, hasLength(1));
    expect(mapped.attachments.single.name, 'photo.png');
    expect(mapped.attachments.single.isImage, isTrue);
    expect(mapped.attachments.single.size, 2048);
  });

  test('maps legacy attachments and actions into rich domain content', () {
    final MattermostPostDto post = MattermostPostDto.fromJson(<String, Object?>{
      'id': 'post-1',
      'user_id': 'ada',
      'channel_id': 'channel-1',
      'message': '',
      'props': <String, Object?>{
        'attachments': <Object?>[
          <String, Object?>{
            'fallback': 'Deployment needs approval',
            'color': '#112233',
            'pretext': 'Production',
            'author_name': 'Release bot',
            'author_link': 'https://example.com/author',
            'author_icon': 'https://example.com/author.png',
            'title': 'Deploy?',
            'title_link': 'https://example.com/deploy',
            'text': '**Ready**',
            'fields': <Object?>[
              <String, Object?>{
                'title': 'Environment',
                'value': 'Production',
                'short': true,
              },
            ],
            'image_url': 'https://example.com/image.png',
            'thumb_url': 'https://example.com/thumb.png',
            'footer': 'Automation',
            'footer_icon': 'https://example.com/footer.png',
            'ts': 1767225600,
            'actions': <Object?>[
              <String, Object?>{
                'id': 'approve',
                'name': 'Approve',
                'type': 'button',
                'tooltip': 'Approve deployment',
                'style': '#00aaff',
                'cookie': 'opaque-token',
              },
              <String, Object?>{
                'id': 'owner',
                'name': 'Owner',
                'type': 'select',
                'data_source': 'users',
                'default_option': 'user-1',
                'options': <Object?>[
                  <String, Object?>{'text': 'Ada', 'value': 'user-1'},
                ],
              },
              <String, Object?>{
                'id': 'schedule',
                'name': 'Schedule',
                'type': 'date_picker',
              },
            ],
          },
        ],
      },
    });

    final Post mapped = _mapSingle(post);

    expect(mapped.message, isEmpty);
    expect(mapped.hasVisibleContent, isTrue);
    final RichAttachment attachment = mapped.richAttachments.single;
    expect(attachment.fallback, 'Deployment needs approval');
    expect(attachment.authorIconUrl, 'https://example.com/author.png');
    expect(attachment.thumbnailUrl, 'https://example.com/thumb.png');
    expect(attachment.fields.single.isShort, isTrue);
    expect(
      attachment.timestamp,
      DateTime.fromMillisecondsSinceEpoch(1767225600000),
    );

    final RichAttachmentButtonAction button =
        attachment.actions[0] as RichAttachmentButtonAction;
    expect(button.tooltip, 'Approve deployment');
    expect(button.style, RichAttachmentButtonStyle.customColor);
    expect(button.customColor, '#00aaff');
    expect(button.token?.value, 'opaque-token');

    final RichAttachmentSelectAction select =
        attachment.actions[1] as RichAttachmentSelectAction;
    expect(select.dataSource, RichAttachmentSelectDataSource.users);
    expect(select.defaultOption, 'user-1');
    expect(select.options.single.value, 'user-1');

    final RichAttachmentUnknownAction unknown =
        attachment.actions[2] as RichAttachmentUnknownAction;
    expect(unknown.type, 'date_picker');
  });

  test('maps semantic button styles and unknown select data sources', () {
    final MattermostPostDto post = MattermostPostDto.fromJson(<String, Object?>{
      'id': 'post-1',
      'user_id': 'ada',
      'channel_id': 'channel-1',
      'message': '',
      'props': <String, Object?>{
        'attachments': <Object?>[
          <String, Object?>{
            'actions': <Object?>[
              for (final String style in <String>[
                'default',
                'primary',
                'good',
                'success',
                'warning',
                'danger',
                'future-style',
              ])
                <String, Object?>{
                  'id': style,
                  'name': style,
                  'type': 'button',
                  'style': style,
                },
              <String, Object?>{
                'id': 'select',
                'name': 'Select',
                'type': 'select',
                'data_source': 'future-source',
              },
            ],
          },
        ],
      },
    });

    final List<RichAttachmentAction> actions = _mapSingle(
      post,
    ).richAttachments.single.actions;
    expect(
      actions.whereType<RichAttachmentButtonAction>().map(
        (RichAttachmentButtonAction action) => action.style,
      ),
      <RichAttachmentButtonStyle>[
        RichAttachmentButtonStyle.defaultStyle,
        RichAttachmentButtonStyle.primary,
        RichAttachmentButtonStyle.good,
        RichAttachmentButtonStyle.success,
        RichAttachmentButtonStyle.warning,
        RichAttachmentButtonStyle.danger,
        RichAttachmentButtonStyle.unknown,
      ],
    );
    expect(
      (actions.last as RichAttachmentSelectAction).dataSource,
      RichAttachmentSelectDataSource.unknown,
    );
  });

  test('ignores an out-of-range rich attachment timestamp', () {
    final MattermostPostDto post = MattermostPostDto.fromJson(<String, Object?>{
      'id': 'post-1',
      'user_id': 'ada',
      'channel_id': 'channel-1',
      'message': '',
      'props': <String, Object?>{
        'attachments': <Object?>[
          <String, Object?>{'title': 'Still visible', 'ts': 1e100},
        ],
      },
    });

    final Post mapped = _mapSingle(post);

    expect(mapped.richAttachments.single.timestamp, isNull);
    expect(mapped.hasVisibleContent, isTrue);
  });

  test('clears all former content when mapping a deleted post', () {
    final MattermostPostDto post = MattermostPostDto.fromJson(<String, Object?>{
      'id': 'post-1',
      'user_id': 'ada',
      'channel_id': 'channel-1',
      'message': 'Former message',
      'delete_at': 42,
      'props': <String, Object?>{
        'attachments': <Object?>[
          <String, Object?>{'title': 'Former card'},
        ],
      },
      'metadata': <String, Object?>{
        'files': <Object?>[
          <String, Object?>{
            'id': 'file-1',
            'user_id': 'ada',
            'post_id': 'post-1',
            'name': 'former.txt',
            'size': 1,
            'mime_type': 'text/plain',
          },
        ],
      },
    });

    final Post mapped = _mapSingle(post, includeDeleted: true);

    expect(mapped.isDeleted, isTrue);
    expect(mapped.message, isEmpty);
    expect(mapped.attachments, isEmpty);
    expect(mapped.richAttachments, isEmpty);
    expect(mapped.hasVisibleContent, isFalse);
  });

  test('hasVisibleContent includes files but ignores whitespace-only text', () {
    final Post empty = Post(
      id: 'empty',
      channelId: 'channel-1',
      author: PostAuthor(id: 'ada', displayName: 'Ada'),
      sentAt: DateTime.fromMillisecondsSinceEpoch(0),
      message: '  \n ',
    );
    final Post withFile = Post(
      id: 'file',
      channelId: 'channel-1',
      author: PostAuthor(id: 'ada', displayName: 'Ada'),
      sentAt: DateTime.fromMillisecondsSinceEpoch(0),
      message: '',
      attachments: <PostAttachment>[
        PostAttachment(
          id: 'file-1',
          name: 'file.txt',
          size: 1,
          mimeType: 'text/plain',
        ),
      ],
    );

    expect(empty.hasVisibleContent, isFalse);
    expect(withFile.hasVisibleContent, isTrue);
  });
}

Post _mapSingle(MattermostPostDto post, {bool includeDeleted = false}) =>
    const MattermostMessageMapper()
        .map(
          posts: <MattermostPostDto>[post],
          users: const <UserSummary>[],
          currentUserId: 'ada',
          includeDeleted: includeDeleted,
        )
        .single;
