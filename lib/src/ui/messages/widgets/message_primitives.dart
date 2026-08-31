import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/models/mattermost_system_emojis.g.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/user_avatar.dart';
import 'package:mattermost_flutter/src/domain/models/user_mention.dart';
import 'package:mattermost_flutter/src/ui/core/widgets/avatar_initials.dart';
import 'package:mattermost_flutter/src/ui/messages/mattermost_markdown.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';
import 'package:mattermost_flutter/src/ui/users/widgets/user_profile_card.dart';

class MessageAvatar extends ConsumerWidget {
  const MessageAvatar({required this.author, this.radius = 19, super.key});

  final PostAuthor author;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<UserAvatar?> avatar = ref.watch(
      userAvatarProvider((
        userId: author.id,
        profileImageUpdatedAt: author.profileImageUpdatedAt,
      )),
    );
    final Widget fallback = CircleAvatar(
      radius: radius,
      backgroundColor: _avatarColor(author.id),
      foregroundColor: Colors.white,
      child: Text(
        avatarInitials(author.displayName),
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: Colors.white),
      ),
    );
    final double diameter = radius * 2;
    final int cacheWidth = (diameter * MediaQuery.devicePixelRatioOf(context))
        .ceil();
    final Widget image = SizedBox.square(
      dimension: diameter,
      child: ClipOval(
        child: avatar.when(
          data: (UserAvatar? value) => value == null
              ? fallback
              : Image.memory(
                  value.bytes,
                  fit: BoxFit.cover,
                  cacheWidth: cacheWidth,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                  errorBuilder:
                      (BuildContext context, Object _, StackTrace? _) {
                        return fallback;
                      },
                ),
          loading: () => fallback,
          error: (Object _, StackTrace _) => fallback,
        ),
      ),
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
              onMessage: (profile) => ref
                  .read(channelSidebarProvider.notifier)
                  .openDirectMessage(profile),
            ),
            child: Center(child: image),
          ),
        ),
      ),
    );
  }

  static Color _avatarColor(String id) {
    const List<Color> colors = <Color>[
      Color(0xff3f51b5),
      Color(0xff00796b),
      Color(0xffad4b00),
      Color(0xff7b1fa2),
    ];
    final int sum = id.codeUnits.fold(0, (int value, int unit) => value + unit);
    return colors[sum % colors.length];
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
    this.deletedMessage,
    super.key,
  });

  final ChannelPost post;
  final Uri? serverUrl;
  final ValueChanged<String>? onSelectChannel;
  final String? deletedMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextStyle? bodyStyle = Theme.of(context).textTheme.bodyMedium;
    if (post.isDeleted && deletedMessage != null) {
      return Text(
        deletedMessage!,
        style: bodyStyle?.copyWith(fontStyle: FontStyle.italic),
      );
    }
    final Map<String, CustomEmojiReference> customEmojiByName =
        <String, CustomEmojiReference>{
          for (final CustomEmojiReference emoji in post.customEmojis)
            emoji.name: emoji,
        };
    final Map<String, UserMention> mentionsByUsername = ref
        .watch(userMentionsProvider(userMentionLookupKey(post.message)))
        .maybeWhen(
          data: (List<UserMention> mentions) => <String, UserMention>{
            for (final UserMention mention in mentions)
              mention.username.toLowerCase(): mention,
          },
          orElse: () => const <String, UserMention>{},
        );
    final List<String> resolvedMentionNames = mentionsByUsername.keys.toList()
      ..sort();
    return MattermostMarkdown(
      data: post.message,
      serverUrl: serverUrl,
      onTapChannel: onSelectChannel,
      textStyle: bodyStyle,
      inlineParserKey: resolvedMentionNames.join(','),
      inlineReplacements: <MattermostInlineReplacement>[
        MattermostInlineReplacement(
          elementName: 'user-mention',
          pattern: r'\B@([a-zA-Z0-9][a-zA-Z0-9._-]*)',
          startCharacter: 0x40,
          shouldReplace: (String username) =>
              mentionsByUsername.containsKey(username.toLowerCase()),
          builder: (BuildContext context, String username, TextStyle style) {
            final UserMention mention =
                mentionsByUsername[username.toLowerCase()]!;
            return _UserMentionInline(mention: mention, textStyle: style);
          },
        ),
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

class _UserMentionInline extends ConsumerStatefulWidget {
  const _UserMentionInline({required this.mention, required this.textStyle});

  final UserMention mention;
  final TextStyle textStyle;

  @override
  ConsumerState<_UserMentionInline> createState() => _UserMentionInlineState();
}

class _UserMentionInlineState extends ConsumerState<_UserMentionInline> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final TextStyle linkStyle = widget.textStyle.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: _hovered ? TextDecoration.underline : TextDecoration.none,
      decorationColor: Theme.of(context).colorScheme.primary,
    );
    return Semantics(
      button: true,
      link: true,
      label: '@${widget.mention.displayName}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: ValueKey<String>('user-mention-${widget.mention.username}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => showUserProfileCard(
            context,
            userId: widget.mention.userId,
            onMessage: (profile) => ref
                .read(channelSidebarProvider.notifier)
                .openDirectMessage(profile),
          ),
          child: Text('@${widget.mention.displayName}', style: linkStyle),
        ),
      ),
    );
  }
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
