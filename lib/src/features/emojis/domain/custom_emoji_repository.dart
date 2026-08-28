import 'package:mattermost_flutter/src/features/emojis/domain/custom_emoji.dart';

abstract interface class CustomEmojiRepository {
  Future<CustomEmojiContent> getByName({
    required String accountId,
    required String name,
    String emojiId = '',
    int updatedAt = 0,
  });
}
