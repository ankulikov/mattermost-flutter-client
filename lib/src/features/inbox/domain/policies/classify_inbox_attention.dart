import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';

/// Classifies the subset of historical mentions that can be reconstructed from
/// a post body and current notification settings.
///
/// The server remains authoritative for mention counters. Current group
/// membership makes group mentions reconstructable, while presence-dependent
/// `@here` still cannot be faithfully reconstructed after a cold start.
final class InboxAttentionMatch {
  const InboxAttentionMatch({required this.reason, this.groupMentionHandle});

  final InboxAttentionReason reason;
  final String? groupMentionHandle;
}

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
}) => classifyInboxAttentionMatch(
  message: message,
  username: username,
  firstName: firstName,
  mentionKeys: mentionKeys,
  firstNameEnabled: firstNameEnabled,
  channelMentionsEnabled: channelMentionsEnabled,
  ignoreChannelMentions: ignoreChannelMentions,
  allMessagesSubscription: allMessagesSubscription,
  groupMentionNames: groupMentionNames,
)?.reason;

InboxAttentionMatch? classifyInboxAttentionMatch({
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
    return const InboxAttentionMatch(
      reason: InboxAttentionReason.directMention,
    );
  }
  if (firstNameEnabled && firstName.isNotEmpty && message.contains(firstName)) {
    return const InboxAttentionMatch(
      reason: InboxAttentionReason.directMention,
    );
  }
  for (final String key in mentionKeys.split(',')) {
    final String normalized = key.trim().toLowerCase();
    if (normalized.isNotEmpty && _containsToken(lowerMessage, normalized)) {
      return const InboxAttentionMatch(
        reason: InboxAttentionReason.keywordMention,
      );
    }
  }
  for (final String name in groupMentionNames) {
    final String normalized = name.trim().toLowerCase();
    if (normalized.isNotEmpty &&
        _containsMention(lowerMessage, normalized, prefix: '@')) {
      return InboxAttentionMatch(
        reason: InboxAttentionReason.groupMention,
        groupMentionHandle: '@${name.trim()}',
      );
    }
  }
  if (channelMentionsEnabled &&
      !ignoreChannelMentions &&
      (_containsMention(lowerMessage, 'channel', prefix: '@') ||
          _containsMention(lowerMessage, 'all', prefix: '@'))) {
    return const InboxAttentionMatch(
      reason: InboxAttentionReason.channelMention,
    );
  }
  // Send-time presence is absent from REST snapshots, so @here remains
  // intentionally omitted.
  return allMessagesSubscription
      ? const InboxAttentionMatch(
          reason: InboxAttentionReason.allMessagesSubscription,
        )
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
