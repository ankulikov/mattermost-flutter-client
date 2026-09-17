import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/models/mattermost_system_emojis.g.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/policies/user_display_name.dart';
import 'package:mattermost_flutter/src/domain/repositories/message_mapper.dart';

final class MattermostMessageMapper
    implements MessageMapper<MattermostPostDto, UserSummary> {
  const MattermostMessageMapper();

  @override
  List<ChannelPost> map({
    required Iterable<MattermostPostDto> posts,
    required Iterable<UserSummary> users,
    required String currentUserId,
    bool includeDeleted = false,
  }) {
    final Map<String, UserSummary> authors = <String, UserSummary>{
      for (final UserSummary user in users) user.id: user,
    };
    return posts
        .where((MattermostPostDto post) => includeDeleted || post.deleteAt == 0)
        .map(
          (MattermostPostDto post) => ChannelPost(
            id: post.id,
            channelId: post.channelId,
            author: _mapAuthor(post.userId, authors[post.userId]),
            sentAt: DateTime.fromMillisecondsSinceEpoch(post.createAt),
            message: post.deleteAt == 0 ? post.message : '',
            customEmojis: post.deleteAt == 0
                ? (post.metadata?.emojis ?? const <MattermostEmojiDto>[])
                      .where(
                        (MattermostEmojiDto emoji) =>
                            emoji.name.isNotEmpty && emoji.deleteAt == 0,
                      )
                      .map(
                        (MattermostEmojiDto emoji) => CustomEmojiReference(
                          name: emoji.name,
                          id: emoji.id,
                          updatedAt: emoji.updateAt,
                        ),
                      )
                      .toList(growable: false)
                : const <CustomEmojiReference>[],
            attachments: post.deleteAt == 0
                ? (post.metadata?.files ?? const <MattermostFileInfoDto>[])
                      .where(
                        (MattermostFileInfoDto file) =>
                            file.id.isNotEmpty && file.deleteAt == 0,
                      )
                      .map(
                        (MattermostFileInfoDto file) => PostAttachment(
                          id: file.id,
                          name: file.name,
                          size: file.size,
                          mimeType: file.mimeType,
                          extension: file.extension,
                          width: file.width,
                          height: file.height,
                          hasPreviewImage: file.hasPreviewImage,
                        ),
                      )
                      .toList(growable: false)
                : const <PostAttachment>[],
            richAttachments: post.deleteAt == 0
                ? _mapRichAttachments(post.props?.legacyAttachments)
                : const <RichAttachment>[],
            rootId: post.rootId,
            replyCount: post.replyCount,
            isDeleted: post.deleteAt != 0,
            lastReplyAt: post.lastReplyAt == 0
                ? null
                : DateTime.fromMillisecondsSinceEpoch(post.lastReplyAt),
            reactions: post.deleteAt == 0
                ? _mapReactions(post, currentUserId)
                : const <PostReaction>[],
          ),
        )
        .toList(growable: false);
  }
}

PostAuthor _mapAuthor(String userId, UserSummary? user) => PostAuthor(
  id: userId,
  displayName: user == null ? userId : _displayName(user),
  profileImageUpdatedAt: user?.profileImageUpdatedAt ?? 0,
);

String _displayName(UserSummary user) => resolveUserDisplayName(
  id: user.id,
  username: user.username,
  nickname: user.nickname,
  firstName: user.firstName,
  lastName: user.lastName,
);

List<PostReaction> _mapReactions(MattermostPostDto post, String currentUserId) {
  final Map<String, List<MattermostReactionDto>> grouped =
      <String, List<MattermostReactionDto>>{};
  for (final MattermostReactionDto reaction
      in post.metadata?.reactions ?? const <MattermostReactionDto>[]) {
    grouped
        .putIfAbsent(reaction.emojiName, () => <MattermostReactionDto>[])
        .add(reaction);
  }
  return grouped.entries
      .map(
        (MapEntry<String, List<MattermostReactionDto>> entry) => PostReaction(
          emoji: _emojiLabel(entry.key),
          emojiName: entry.key,
          count: entry.value.length,
          reactedByCurrentUser: entry.value.any(
            (MattermostReactionDto reaction) =>
                reaction.userId == currentUserId,
          ),
        ),
      )
      .toList(growable: false);
}

String _emojiLabel(String name) => mattermostSystemEmojis[name] ?? ':$name:';

List<RichAttachment> _mapRichAttachments(
  List<MattermostLegacyAttachmentDto>? attachments,
) => (attachments ?? const <MattermostLegacyAttachmentDto>[])
    .map(
      (MattermostLegacyAttachmentDto attachment) => RichAttachment(
        fallback: attachment.fallback,
        color: attachment.color,
        pretext: attachment.pretext,
        authorName: attachment.authorName,
        authorLink: attachment.authorLink,
        authorIconUrl: attachment.authorIcon,
        title: attachment.title,
        titleLink: attachment.titleLink,
        text: attachment.text,
        fields: attachment.fields
            .map(
              (MattermostLegacyAttachmentFieldDto field) => RichAttachmentField(
                title: field.title,
                value: field.value,
                isShort: field.isShort,
              ),
            )
            .toList(growable: false),
        imageUrl: attachment.imageUrl,
        thumbnailUrl: attachment.thumbUrl,
        footer: attachment.footer,
        footerIconUrl: attachment.footerIcon,
        timestamp: _mapAttachmentTimestamp(attachment.timestamp),
        actions: attachment.actions
            .map(_mapRichAttachmentAction)
            .toList(growable: false),
      ),
    )
    .toList(growable: false);

RichAttachmentAction _mapRichAttachmentAction(
  MattermostLegacyActionDto action,
) {
  final RichAttachmentActionToken? token = switch (action.cookie) {
    final String value when value.isNotEmpty => RichAttachmentActionToken(
      value,
    ),
    _ => null,
  };
  return switch (action) {
    MattermostLegacyButtonActionDto() => _mapButtonAction(action, token),
    MattermostLegacySelectActionDto() => RichAttachmentSelectAction(
      id: action.id,
      name: action.name,
      token: token,
      options: action.options
          .map(
            (MattermostLegacyActionOptionDto option) =>
                RichAttachmentOption(text: option.text, value: option.value),
          )
          .toList(growable: false),
      defaultOption: action.defaultOption,
      dataSource: _mapSelectDataSource(action.dataSource),
    ),
    MattermostLegacyUnknownActionDto() => RichAttachmentUnknownAction(
      id: action.id,
      name: action.name,
      type: action.type,
      token: token,
    ),
  };
}

RichAttachmentButtonAction _mapButtonAction(
  MattermostLegacyButtonActionDto action,
  RichAttachmentActionToken? token,
) {
  final String trimmedStyle = action.style.trim();
  final String normalizedStyle = trimmedStyle.toLowerCase();
  final RichAttachmentButtonStyle style = switch (normalizedStyle) {
    '' || 'default' => RichAttachmentButtonStyle.defaultStyle,
    'primary' => RichAttachmentButtonStyle.primary,
    'good' => RichAttachmentButtonStyle.good,
    'success' => RichAttachmentButtonStyle.success,
    'warning' => RichAttachmentButtonStyle.warning,
    'danger' => RichAttachmentButtonStyle.danger,
    _ when _hexColor.hasMatch(normalizedStyle) =>
      RichAttachmentButtonStyle.customColor,
    _ => RichAttachmentButtonStyle.unknown,
  };
  return RichAttachmentButtonAction(
    id: action.id,
    name: action.name,
    token: token,
    tooltip: action.tooltip,
    style: style,
    customColor: style == RichAttachmentButtonStyle.customColor
        ? trimmedStyle
        : '',
  );
}

final RegExp _hexColor = RegExp(
  r'^#(?:[0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$',
  caseSensitive: false,
);

RichAttachmentSelectDataSource? _mapSelectDataSource(String value) =>
    switch (value.trim().toLowerCase()) {
      '' => null,
      'channels' => RichAttachmentSelectDataSource.channels,
      'users' => RichAttachmentSelectDataSource.users,
      _ => RichAttachmentSelectDataSource.unknown,
    };

DateTime? _mapAttachmentTimestamp(JsonValueDto? timestamp) {
  final num? seconds = switch (timestamp) {
    JsonNumberDto(:final num value) => value,
    JsonStringDto(:final String value) => num.tryParse(value),
    _ => null,
  };
  if (seconds == null || !seconds.isFinite) return null;
  final num milliseconds = seconds * 1000;
  const int maxDateTimeMilliseconds = 8640000000000000;
  if (milliseconds < -maxDateTimeMilliseconds ||
      milliseconds > maxDateTimeMilliseconds) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(milliseconds.round());
}
