import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/mattermost_system_emojis.g.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/policies/emoji_search.dart';

void main() {
  test('normalizes shortcode delimiters, spaces, and case', () {
    expect(normalizeEmojiSearchTerm(' :Party Parrot: '), 'party_parrot');
  });

  test('searches aliases and returns the canonical Mattermost emoji', () {
    final results = searchSystemEmojis(mattermostSystemEmojiCatalog, 'rofl');

    expect(results.first.name, 'rolling_on_the_floor_laughing');
    expect(results.first.unicode, '🤣');
  });

  test(
    'orders prefix matches ahead of weaker matches and honors the limit',
    () {
      final results = searchSystemEmojis(
        mattermostSystemEmojiCatalog,
        'thumb',
        limit: 5,
      );

      expect(results, hasLength(5));
      expect(
        results.first.aliases.any((String alias) => alias.startsWith('thumb')),
        isTrue,
      );
      expect(results.map((emoji) => emoji.name).toSet(), hasLength(5));
    },
  );

  test('optimistic system reactions use their unicode glyph', () {
    final Post post = Post(
      id: 'post',
      channelId: 'channel',
      author: const PostAuthor(id: 'user', displayName: 'User'),
      sentAt: DateTime.fromMillisecondsSinceEpoch(1),
      message: 'Hello',
    );

    final Post updated = toggleCurrentUserReaction(post, 'grinning');

    expect(updated.reactions.single.emoji, '😀');
    expect(updated.reactions.single.reactedByCurrentUser, isTrue);
  });
}
