import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/core/ui/avatar_initials.dart';
import 'package:mattermost_flutter/src/core/ui/mattermost_markdown.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message.dart';

class MessageAvatar extends StatelessWidget {
  const MessageAvatar({required this.author, this.radius = 19, super.key});

  final PostAuthor author;
  final double radius;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: author.displayName,
    child: CircleAvatar(
      radius: radius,
      backgroundColor: _avatarColor(author.id),
      foregroundColor: Colors.white,
      child: Text(
        avatarInitials(author.displayName),
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: Colors.white),
      ),
    ),
  );

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
    final String time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(sentAt));
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 2,
      children: <Widget>[
        Text(
          author.displayName,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
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
    return MattermostMarkdown(
      data: post.message,
      serverUrl: serverUrl,
      onTapChannel: onSelectChannel,
      textStyle: bodyStyle,
    );
  }
}
