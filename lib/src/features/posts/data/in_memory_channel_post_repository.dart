import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post_repository.dart';

final class InMemoryChannelPostRepository implements ChannelPostRepository {
  const InMemoryChannelPostRepository({
    this.delay = const Duration(milliseconds: 900),
  });

  final Duration delay;

  static const List<PostAuthor> _authors = <PostAuthor>[
    PostAuthor(id: 'ada', displayName: 'Ada Lovelace'),
    PostAuthor(id: 'grace', displayName: 'Grace Hopper'),
    PostAuthor(id: 'alan', displayName: 'Alan Turing'),
    PostAuthor(id: 'margaret', displayName: 'Margaret Hamilton'),
  ];

  static const List<String> _messages = <String>[
    'Добро пожаловать в канал! Здесь можно обсудить детали и договориться о следующих шагах.',
    'Я собрала короткое резюме. Главный вывод: сначала проверяем основной сценарий, затем добавляем пограничные случаи.',
    'Отлично выглядит. Оставил пару небольших замечаний — они не блокируют дальнейшую работу.',
    'Обновление готово к проверке. Если всё в порядке, можем переходить к следующей части.',
    'Есть идея: давайте сохраним этот пример как основу для будущих обсуждений.',
    'Спасибо! Проверил на узком и широком экранах, поведение осталось стабильным.',
  ];

  Future<List<ChannelPost>> loadHistory(String channelId) async {
    await Future<void>.delayed(delay);

    final int seed = _stableHash(channelId);
    final DateTime baseTime = DateTime(
      2026,
      8,
      24,
      9,
      15,
    ).add(Duration(minutes: seed % 90));
    return List<ChannelPost>.generate(120, (int index) {
      // Three-message runs exercise the compact grouped-message presentation.
      final int authorGroup = index ~/ 3;
      final PostAuthor author =
          _authors[(seed + authorGroup) % _authors.length];
      final int messageIndex = (seed + index * 3) % _messages.length;
      return ChannelPost(
        id: '$channelId-post-$index',
        channelId: channelId,
        author: author,
        sentAt: baseTime.add(Duration(minutes: index * 4)),
        message: _messages[messageIndex],
        reactions: _reactionsFor(seed + index),
      );
    }, growable: false);
  }

  @override
  Future<ChannelPostPage> loadOlder({
    required AuthSession session,
    required String channelId,
    required String beforePostId,
  }) async => const ChannelPostPage();

  @override
  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  }) async =>
      ChannelPostPage(posts: await loadHistory(channelId), hasOlder: false);

  static int _stableHash(String value) {
    var result = 17;
    for (final int codeUnit in value.codeUnits) {
      result = (result * 37 + codeUnit) & 0x7fffffff;
    }
    return result;
  }

  static List<PostReaction> _reactionsFor(int seed) {
    final List<PostReaction> reactions = <PostReaction>[];
    if (seed.isEven) {
      reactions.add(
        PostReaction(
          emoji: '👍',
          count: seed % 4 + 1,
          reactedByCurrentUser: seed % 3 == 0,
        ),
      );
    }
    if (seed % 3 == 0) {
      reactions.add(PostReaction(emoji: '🎉', count: seed % 3 + 1));
    }
    if (seed % 5 == 0) {
      reactions.add(PostReaction(emoji: '❤️', count: seed % 5 + 1));
    }
    return List<PostReaction>.unmodifiable(reactions);
  }
}
