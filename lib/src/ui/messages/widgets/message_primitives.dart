import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/models/mattermost_system_emojis.g.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/models/user_mention.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/group_mention.dart';
import 'package:mattermost_flutter/src/ui/messages/mattermost_markdown.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';
import 'package:mattermost_flutter/src/ui/users/widgets/user_avatar_image.dart';
import 'package:mattermost_flutter/src/ui/users/widgets/user_profile_card.dart';

class MessageAvatar extends ConsumerWidget {
  const MessageAvatar({required this.author, this.radius = 19, super.key});

  final PostAuthor author;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double diameter = radius * 2;
    final Widget image = UserAvatarImage(
      userId: author.id,
      displayName: author.displayName,
      profileImageUpdatedAt: author.profileImageUpdatedAt,
      radius: radius,
    );
    final double tapTarget = diameter < 44 ? 44 : diameter;
    return Semantics(
      button: true,
      image: true,
      label: author.displayName,
      child: SizedBox.square(
        dimension: tapTarget,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showUserProfileCard(
              context,
              userId: author.id,
              onMessage: (UserProfile profile) =>
                  _openDirectMessage(context, ref, profile),
            ),
            child: Center(child: image),
          ),
        ),
      ),
    );
  }
}

class MessageAuthorLine extends StatelessWidget {
  const MessageAuthorLine({
    required this.author,
    required this.sentAt,
    super.key,
  });

  final PostAuthor author;
  final DateTime sentAt;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String timestamp = formatMessageTimestamp(
      sentAt: sentAt,
      locale: Localizations.localeOf(context).toLanguageTag(),
    );
    return Row(
      children: <Widget>[
        Flexible(
          child: Text(
            author.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          timestamp,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

String formatMessageTimestamp({
  required DateTime sentAt,
  required String locale,
  DateTime? now,
}) {
  final DateTime localSentAt = sentAt.toLocal();
  final DateTime localNow = (now ?? DateTime.now()).toLocal();
  final String time = DateFormat.Hm(locale).format(localSentAt);
  if (_isSameDay(localSentAt, localNow)) return time;

  final String month = DateFormat.MMM(
    locale,
  ).format(localSentAt).replaceFirst(RegExp(r'\.$'), '');
  return '${localSentAt.day} $month $time';
}

bool _isSameDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

class MessageBody extends ConsumerWidget {
  const MessageBody({
    required this.post,
    this.serverUrl,
    this.onSelectChannel,
    this.onOpenPostLink,
    this.deletedMessage,
    super.key,
  });

  final ChannelPost post;
  final Uri? serverUrl;
  final ValueChanged<String>? onSelectChannel;
  final ValueChanged<String>? onOpenPostLink;
  final String? deletedMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (post.isDeleted && deletedMessage != null) {
      return Text(
        deletedMessage!,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
      );
    }
    return MessageMarkdown(
      data: post.message,
      customEmojis: post.customEmojis,
      serverUrl: serverUrl,
      onSelectChannel: onSelectChannel,
      onOpenPostLink: onOpenPostLink,
    );
  }
}

/// Shared safe Markdown projection for a post and its rich attachment fields.
///
/// Keeping mentions and permalink behavior here prevents legacy attachment
/// cards from accidentally using a less restrictive rendering path.
class MessageMarkdown extends ConsumerWidget {
  const MessageMarkdown({
    required this.data,
    this.customEmojis = const <CustomEmojiReference>[],
    this.serverUrl,
    this.onSelectChannel,
    this.onOpenPostLink,
    this.textStyle,
    super.key,
  });

  final String data;
  final List<CustomEmojiReference> customEmojis;
  final Uri? serverUrl;
  final ValueChanged<String>? onSelectChannel;
  final ValueChanged<String>? onOpenPostLink;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextStyle? bodyStyle =
        textStyle ?? Theme.of(context).textTheme.bodyMedium;
    final Map<String, CustomEmojiReference> customEmojiByName =
        <String, CustomEmojiReference>{
          for (final CustomEmojiReference emoji in customEmojis)
            emoji.name: emoji,
        };
    final Map<String, UserMention> mentionsByUsername = ref
        .watch(userMentionsProvider(userMentionLookupKey(data)))
        .maybeWhen(
          data: (List<UserMention> mentions) => <String, UserMention>{
            for (final UserMention mention in mentions)
              mention.username.toLowerCase(): mention,
          },
          orElse: () => const <String, UserMention>{},
        );
    final List<String> resolvedMentionNames = mentionsByUsername.keys.toList()
      ..sort();
    final Map<String, GroupMention> groupsByName = ref
        .watch(groupMentionsProvider(userMentionLookupKey(data)))
        .maybeWhen(
          data: (List<GroupMention> groups) => <String, GroupMention>{
            for (final GroupMention group in groups)
              group.name.toLowerCase(): group,
          },
          orElse: () => const <String, GroupMention>{},
        );
    final List<String> resolvedGroupNames = groupsByName.keys.toList()..sort();
    return MattermostMarkdown(
      data: data,
      serverUrl: serverUrl,
      onTapChannel: onSelectChannel,
      onTapPostLink: onOpenPostLink,
      textStyle: bodyStyle,
      inlineParserKey:
          '${resolvedMentionNames.join(',')}|${resolvedGroupNames.join(',')}',
      inlineLinkReplacements: <MattermostInlineLinkReplacement>[
        MattermostInlineLinkReplacement(
          elementName: 'resolved-mention',
          pattern: r'\B@([a-zA-Z0-9][a-zA-Z0-9._-]*)',
          startCharacter: 0x40,
          shouldReplace: (String name) {
            final String normalized = name.toLowerCase();
            return mentionsByUsername.containsKey(normalized) ||
                groupsByName.containsKey(normalized);
          },
          textBuilder: (String name) {
            final UserMention? mention = mentionsByUsername[name.toLowerCase()];
            return mention == null ? '@$name' : '@${mention.displayName}';
          },
          onTap: (BuildContext context, String name) {
            final UserMention? mention = mentionsByUsername[name.toLowerCase()];
            if (mention == null) return;
            showUserProfileCard(
              context,
              userId: mention.userId,
              onMessage: (UserProfile profile) =>
                  _openDirectMessage(context, ref, profile),
            );
          },
        ),
      ],
      inlineReplacements: <MattermostInlineReplacement>[
        MattermostInlineReplacement(
          elementName: 'custom-emoji',
          pattern: r':([a-z0-9_+-]+):',
          startCharacter: 0x3a,
          shouldReplace: (String name) =>
              !mattermostSystemEmojis.containsKey(name),
          fallbackText: (String name) => mattermostSystemEmojis[name],
          builder: (BuildContext context, String name, TextStyle style) {
            final CustomEmojiReference reference =
                customEmojiByName[name] ?? CustomEmojiReference(name: name);
            return _CustomEmojiInline(reference: reference, textStyle: style);
          },
        ),
      ],
    );
  }
}

Future<void> _openDirectMessage(
  BuildContext context,
  WidgetRef ref,
  UserProfile profile,
) async {
  await ref.read(channelSidebarProvider.notifier).openDirectMessage(profile);
  if (context.mounted) context.go('/');
}

class MessageReactions extends StatelessWidget {
  const MessageReactions({
    required this.post,
    required this.semanticsLabel,
    required this.onToggle,
    super.key,
  });

  final ChannelPost post;
  final String semanticsLabel;
  final Future<void> Function(PostReaction reaction) onToggle;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      children: post.reactions
          .map(
            (PostReaction reaction) => _ReactionButton(
              reaction: reaction,
              customEmoji: _customEmojiFor(post, reaction),
              onPressed: () => unawaited(onToggle(reaction)),
            ),
          )
          .toList(growable: false),
    ),
  );

  static CustomEmojiReference? _customEmojiFor(
    ChannelPost post,
    PostReaction reaction,
  ) {
    for (final CustomEmojiReference emoji in post.customEmojis) {
      if (emoji.name == reaction.emojiName) return emoji;
    }
    final String label = reaction.emoji;
    if (label.length > 2 && label.startsWith(':') && label.endsWith(':')) {
      return CustomEmojiReference(name: reaction.emojiName);
    }
    return null;
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.reaction,
    required this.customEmoji,
    required this.onPressed,
  });

  final PostReaction reaction;
  final CustomEmojiReference? customEmoji;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color background = reaction.reactedByCurrentUser
        ? colors.primary.withValues(alpha: 0.1)
        : colors.surfaceContainerHighest.withValues(alpha: 0.72);
    final Color border = reaction.reactedByCurrentUser
        ? colors.primary
        : colors.outlineVariant;
    return Semantics(
      button: true,
      selected: reaction.reactedByCurrentUser,
      label: '${reaction.emoji}: ${reaction.count}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: ValueKey<String>('reaction-${reaction.emojiName}'),
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: DecoratedBox(
                key: ValueKey<String>('reaction-chip-${reaction.emojiName}'),
                decoration: BoxDecoration(
                  color: background,
                  border: Border.all(
                    color: border,
                    width: reaction.reactedByCurrentUser ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (customEmoji case final CustomEmojiReference emoji)
                        _CustomEmojiReaction(reference: emoji)
                      else
                        _ReactionEmojiGlyph(
                          emoji: reaction.emoji,
                          emojiName: reaction.emojiName,
                        ),
                      const SizedBox(width: 5),
                      Text(
                        '${reaction.count}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReactionEmojiGlyph extends StatelessWidget {
  const _ReactionEmojiGlyph({required this.emoji, required this.emojiName});

  final String emoji;
  final String emojiName;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    key: ValueKey<String>('reaction-icon-$emojiName'),
    dimension: _reactionEmojiSize,
    child: FittedBox(
      fit: BoxFit.contain,
      child: Text(
        emoji,
        style: const TextStyle(fontSize: _reactionEmojiSize, height: 1),
      ),
    ),
  );
}

const double _reactionEmojiSize = 20;

class _CustomEmojiReaction extends ConsumerWidget {
  const _CustomEmojiReaction({required this.reference});

  final CustomEmojiReference reference;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CustomEmojiContent> content = ref.watch(
      customEmojiProvider(reference),
    );
    final int cacheSize =
        (_reactionEmojiSize * MediaQuery.devicePixelRatioOf(context)).ceil();
    const Widget fallback = Icon(
      Icons.emoji_emotions_outlined,
      size: _reactionEmojiSize,
    );
    return SizedBox.square(
      key: ValueKey<String>('reaction-icon-${reference.name}'),
      dimension: _reactionEmojiSize,
      child: content.when(
        data: (CustomEmojiContent emoji) => Image.memory(
          emoji.bytes,
          fit: BoxFit.contain,
          cacheWidth: cacheSize,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => fallback,
        ),
        loading: () => fallback,
        error: (_, _) => fallback,
      ),
    );
  }
}

class _CustomEmojiInline extends ConsumerWidget {
  const _CustomEmojiInline({required this.reference, required this.textStyle});

  final CustomEmojiReference reference;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CustomEmojiContent> content = ref.watch(
      customEmojiProvider(reference),
    );
    final String shortcode = ':${reference.name}:';
    final Widget fallback = Text(shortcode, style: textStyle);
    final double logicalSize = MediaQuery.textScalerOf(
      context,
    ).scale(textStyle.fontSize ?? 14);
    final int cacheSize = (logicalSize * MediaQuery.devicePixelRatioOf(context))
        .ceil();
    return Semantics(
      image: content.hasValue,
      label: shortcode,
      child: content.when(
        data: (CustomEmojiContent emoji) => SizedBox.square(
          dimension: logicalSize,
          child: Image.memory(
            emoji.bytes,
            fit: BoxFit.cover,
            cacheWidth: cacheSize,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => fallback,
          ),
        ),
        loading: () => fallback,
        error: (_, _) => fallback,
      ),
    );
  }
}
