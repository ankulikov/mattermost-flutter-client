import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_strings.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_spacing.dart';
import 'package:mattermost_flutter/src/ui/core/widgets/relative_time.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_section_divider.dart';

final _replyClockProvider = StreamProvider.autoDispose<DateTime>(
  (Ref ref) => Stream<DateTime>.periodic(
    const Duration(minutes: 1),
    (_) => DateTime.now(),
  ),
);

/// Text-only recent replies within the root message's Inbox card.
class InboxThreadReplies extends StatelessWidget {
  const InboxThreadReplies({required this.replies, super.key});

  final List<Post> replies;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppLayout.cardPadding,
        0,
        AppLayout.cardPadding,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MessageSectionDivider(
            label: InboxStrings.recentMessages(replies.length),
            bottomSpacing: 4,
          ),
          for (final Post reply in replies)
            Row(
              key: ValueKey<String>('inbox-reply-${reply.id}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MessageAvatar(author: reply.author, radius: 12),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _ReplyTimestamp(reply: reply),
                        const SizedBox(height: 2),
                        Text(
                          _preview(reply.message),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _preview(String message) {
    final Characters characters = message.characters.take(101);
    final String text = characters
        .take(100)
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ');
    return characters.length > 100 ? '$text…' : text;
  }
}

class _ReplyTimestamp extends ConsumerWidget {
  const _ReplyTimestamp({required this.reply});

  final Post reply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DateTime now = ref.watch(_replyClockProvider).value ?? DateTime.now();
    return Text(
      formatFollowedThreadLastReplyTime(
        lastReplyAt: reply.sentAt,
        now: now,
        localizations: MaterialLocalizations.of(context),
      ),
      key: ValueKey<String>('inbox-reply-time-${reply.id}'),
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
