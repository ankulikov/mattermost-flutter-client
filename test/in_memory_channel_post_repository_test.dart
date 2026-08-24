import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/posts/data/in_memory_channel_post_repository.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';

void main() {
  test('generates stable channel-specific post history', () async {
    const InMemoryChannelPostRepository repository =
        InMemoryChannelPostRepository(delay: Duration.zero);

    final List<ChannelPost> first = await repository.loadHistory('town-square');
    final List<ChannelPost> repeated = await repository.loadHistory(
      'town-square',
    );
    final List<ChannelPost> other = await repository.loadHistory('off-topic');

    expect(first, hasLength(120));
    expect(first.map((ChannelPost post) => post.id), <String>[
      for (var index = 0; index < 120; index++) 'town-square-post-$index',
    ]);
    expect(
      repeated.map((ChannelPost post) => post.message),
      first.map((ChannelPost post) => post.message),
    );
    expect(other.first.id, isNot(first.first.id));
    expect(
      first.every((ChannelPost post) => post.channelId == 'town-square'),
      isTrue,
    );
    expect(first[0].author.id, first[1].author.id);
    expect(first[1].author.id, first[2].author.id);
    expect(first[2].author.id, isNot(first[3].author.id));
  });
}
