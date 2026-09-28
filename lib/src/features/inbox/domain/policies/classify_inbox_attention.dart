import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';

/// Classifies the subset of historical mentions that can be reconstructed from
/// a post body and current notification settings.
///
/// The server remains authoritative for mention counters. Current group
/// membership makes group mentions reconstructable, while presence-dependent
/// `@here` still cannot be faithfully reconstructed after a cold start.
InboxAttentionReason? classifyInboxAttention({
  required String message,
  required String username,
  required String firstName,
  required String mentionKeys,
  required bool firstNameEnabled,
  required bool channelMentionsEnabled,
  required bool ignoreChannelMentions,
  required bool allMessagesSubscription,
  Iterable<String> groupMentionNames = const <String>[],
}) {
  final String lowerMessage = message.toLowerCase();
  if (_containsMention(lowerMessage, username.toLowerCase(), prefix: '@')) {
    return InboxAttentionReason.directMention;
  }
  if (firstNameEnabled && firstName.isNotEmpty && message.contains(firstName)) {
    return InboxAttentionReason.directMention;
  }
  for (final String key in mentionKeys.split(',')) {
    final String normalized = key.trim().toLowerCase();
    if (normalized.isNotEmpty && _containsToken(lowerMessage, normalized)) {
      return InboxAttentionReason.keywordMention;
    }
  }
  for (final String name in groupMentionNames) {
    final String normalized = name.trim().toLowerCase();
    if (normalized.isNotEmpty &&
        _containsMention(lowerMessage, normalized, prefix: '@')) {
      return InboxAttentionReason.groupMention;
    }
  }
  if (channelMentionsEnabled &&
      !ignoreChannelMentions &&
      (_containsMention(lowerMessage, 'channel', prefix: '@') ||
          _containsMention(lowerMessage, 'all', prefix: '@'))) {
    return InboxAttentionReason.channelMention;
  }
  // Send-time presence is absent from REST snapshots, so @here remains
  // intentionally omitted.
  return allMessagesSubscription
      ? InboxAttentionReason.allMessagesSubscription
      : null;
}

bool _containsMention(String message, String value, {required String prefix}) =>
    value.isNotEmpty && _containsToken(message, '$prefix$value');

bool _containsToken(String text, String token) {
  var start = 0;
  while (start < text.length) {
    final int index = text.indexOf(token, start);
    if (index < 0) return false;
    final int before = index - 1;
    final int after = index + token.length;
    final bool validBefore = before < 0 || !_isWord(text.codeUnitAt(before));
    final bool validAfter =
        after >= text.length || !_isWord(text.codeUnitAt(after));
    if (validBefore && validAfter) return true;
    start = index + token.length;
  }
  return false;
}

bool _isWord(int codeUnit) =>
    (codeUnit >= 48 && codeUnit <= 57) ||
    (codeUnit >= 65 && codeUnit <= 90) ||
    (codeUnit >= 97 && codeUnit <= 122) ||
    codeUnit == 95;
