import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
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
          users: const <MattermostUserDto>[
            MattermostUserDto(id: 'ada', username: 'ada'),
          ],
          currentUserId: 'ada',
        )
        .single;

    expect(mapped.customEmojis, hasLength(1));
    expect(mapped.customEmojis.single.name, 'party_parrot');
    expect(mapped.customEmojis.single.id, 'emoji-1');
    expect(mapped.customEmojis.single.updatedAt, 42);
  });
}
