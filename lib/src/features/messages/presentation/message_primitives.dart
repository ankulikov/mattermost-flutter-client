import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:mattermost_flutter/src/app/di/app_providers.dart';
import 'package:mattermost_flutter/src/core/ui/avatar_initials.dart';
import 'package:mattermost_flutter/src/core/ui/mattermost_markdown.dart';
import 'package:mattermost_flutter/src/features/emojis/domain/custom_emoji.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_avatar.dart';
import 'package:mattermost_flutter/src/features/users/presentation/user_profile_card.dart';

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
              onMessage: (profile) => openDirectMessage(ref, profile),
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

class MessageAuthorLine extends ConsumerWidget {
  const MessageAuthorLine({
    required this.author,
    required this.sentAt,
    super.key,
  });

  final PostAuthor author;
  final DateTime sentAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final String time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(sentAt));
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 2,
      children: <Widget>[
        Semantics(
          button: true,
          child: InkWell(
            onTap: () => showUserProfileCard(
              context,
              userId: author.id,
              onMessage: (profile) => openDirectMessage(ref, profile),
            ),
            borderRadius: BorderRadius.circular(4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  author.displayName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
        Text(
          time,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class MessageBody extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
    return MattermostMarkdown(
      data: post.message,
      serverUrl: serverUrl,
      onTapChannel: onSelectChannel,
      textStyle: bodyStyle,
      inlineReplacements: <MattermostInlineReplacement>[
        MattermostInlineReplacement(
          elementName: 'custom-emoji',
          pattern: r':([a-z0-9_+-]+):',
          startCharacter: 0x3a,
          shouldReplace: (String name) => !md.emojis.containsKey(name),
          fallbackText: (String name) => md.emojis[name],
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
