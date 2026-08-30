import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/messages/data/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message.dart';

void main() {
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
}
