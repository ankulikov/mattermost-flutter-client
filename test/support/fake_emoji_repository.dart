import 'dart:convert';
import 'dart:typed_data';

import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/repositories/emoji_repository.dart';

final class FakeEmojiRepository implements CustomEmojiRepository {
  List<String> recent = <String>[];
  List<CustomEmojiReference> page = <CustomEmojiReference>[];
  List<CustomEmojiReference> searchResults = <CustomEmojiReference>[];
  final List<String> searchedTerms = <String>[];
  final List<String> remembered = <String>[];

  @override
  Future<List<CustomEmojiReference>> getPage({
    required String accountId,
    int page = 0,
    int perPage = 90,
  }) async => page == 0 ? this.page : const <CustomEmojiReference>[];

  @override
  Future<List<CustomEmojiReference>> search({
    required String accountId,
    required String term,
  }) async {
    searchedTerms.add(term);
    return searchResults;
  }

  @override
  Future<CustomEmojiContent> getByName({
    required String accountId,
    required String name,
    String emojiId = '',
    int updatedAt = 0,
  }) async => CustomEmojiContent(bytes: _transparentPng);

  @override
  Future<List<String>> getRecent({required String accountId}) async => recent;

  @override
  Future<void> rememberRecent({
    required String accountId,
    required String emojiName,
  }) async {
    remembered.add(emojiName);
    recent = <String>[
      emojiName,
      ...recent.where((String value) => value != emojiName),
    ];
  }
}

final Uint8List _transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/'
  'l1ZQAAAAAElFTkSuQmCC',
);
