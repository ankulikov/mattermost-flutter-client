import 'package:mattermost_flutter/src/domain/models/emoji.dart';

abstract interface class CustomEmojiRepository {
  Future<CustomEmojiContent> getByName({
    required String accountId,
    required String name,
    String emojiId = '',
    int updatedAt = 0,
  });
}
