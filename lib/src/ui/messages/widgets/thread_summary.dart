import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/ui/messages/thread_summary_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';

class ThreadSummary extends StatelessWidget {
  const ThreadSummary({required this.thread, super.key});

  final FollowedThread thread;

  static const double _avatarHitTarget = 44;
  static const double _avatarRadius = 12;
  static const double _avatarOverlap = 4;

  List<PostAuthor> get _visibleParticipants => thread.participants.length > 4
      ? thread.participants.take(3).toList(growable: false)
      : thread.participants.take(4).toList(growable: false);

  List<PostAuthor> get _remainingParticipants => thread.participants.length > 4
      ? thread.participants.skip(3).toList(growable: false)
      : const <PostAuthor>[];

  double get _participantStripWidth =>
      _avatarHitTarget +
      (_visibleParticipants.length +
              (_remainingParticipants.isEmpty ? 0 : 1) -
              1) *
          (_avatarRadius * 2 - _avatarOverlap);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<PostAuthor> participants = _visibleParticipants;
    final List<PostAuthor> remainingParticipants = _remainingParticipants;
    return Padding(
      key: ValueKey<String>('thread-participant-summary-${thread.id}'),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Center(
              child: thread.unreadReplies > 0 || thread.unreadMentions > 0
                  ? _UnreadIndicator(thread: thread)
                  : null,
            ),
          ),
          const SizedBox(width: 2),
          if (participants.isNotEmpty)
            SizedBox(
              width: _participantStripWidth,
              height: _avatarHitTarget,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  for (int index = 0; index < participants.length; index += 1)
                    PositionedDirectional(
                      start: index * (_avatarRadius * 2 - _avatarOverlap),
                      child: MessageAvatar(
                        author: participants[index],
                        radius: _avatarRadius,
                      ),
                    ),
                  if (remainingParticipants.isNotEmpty)
                    PositionedDirectional(
                      start:
                          participants.length *
                          (_avatarRadius * 2 - _avatarOverlap),
                      child: _RemainingParticipantsCounter(
                        threadId: thread.id,
                        participants: remainingParticipants,
                      ),
                    ),
                ],
              ),
            ),
          if (participants.isNotEmpty) const SizedBox(width: 8),
          Expanded(
            child: Text(
              thread.unreadReplies > 0
                  ? ThreadSummaryStrings.newReplies(thread.unreadReplies)
                  : ThreadSummaryStrings.replies(thread.replyCount),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemainingParticipantsCounter extends StatelessWidget {
  const _RemainingParticipantsCounter({
    required this.threadId,
    required this.participants,
  });

  final String threadId;
  final List<PostAuthor> participants;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final String names = _tooltipNames(participants);
    return Tooltip(
      message: names,
      child: Semantics(
        label: ThreadSummaryStrings.additionalParticipants(participants.length),
        child: SizedBox.square(
          dimension: ThreadSummary._avatarHitTarget,
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            child: Center(
              child: DecoratedBox(
                key: ValueKey<String>(
                  'thread-additional-participants-$threadId',
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: ThreadSummary._avatarRadius * 2,
                  child: Center(
                    child: Text(
                      '+${participants.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _tooltipNames(List<PostAuthor> participants) {
    final List<String> rows = <String>[];
    for (int index = 0; index < participants.length; index += 2) {
      rows.add(
        participants
            .skip(index)
            .take(2)
            .map((PostAuthor participant) => participant.displayName)
            .join(', '),
      );
    }
    return rows.join('\n');
  }
}

class _UnreadIndicator extends StatelessWidget {
  const _UnreadIndicator({required this.thread});

  final FollowedThread thread;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    if (thread.unreadMentions > 0) {
      return Semantics(
        label: ThreadSummaryStrings.mentions(thread.unreadMentions),
        child: Container(
          key: ValueKey<String>('thread-unread-count-${thread.id}'),
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.primary,
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${thread.unreadMentions}',
                style: TextStyle(
                  color: colors.onPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Semantics(
      label: ThreadSummaryStrings.unreadReplies(thread.unreadReplies),
      child: Container(
        key: ValueKey<String>('thread-unread-dot-${thread.id}'),
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: colors.primary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
