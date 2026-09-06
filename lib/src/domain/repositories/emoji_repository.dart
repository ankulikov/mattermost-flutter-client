import 'package:mattermost_flutter/src/domain/models/emoji.dart';

abstract interface class CustomEmojiRepository {
  Future<List<CustomEmojiReference>> getPage({
    required String accountId,
    int page = 0,
    int perPage = 90,
  });

  Future<List<CustomEmojiReference>> search({
    required String accountId,
    required String term,
  });

  Future<CustomEmojiContent> getByName({
    required String accountId,
    required String name,
    String emojiId = '',
    int updatedAt = 0,
  });

  Future<List<String>> getRecent({required String accountId});

  Future<void> rememberRecent({
    required String accountId,
    required String emojiName,
  });
}
