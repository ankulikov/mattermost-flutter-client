import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_candidate.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_search_result.dart';
import 'package:mattermost_flutter/src/features/mentions/presentation/mention_autocomplete_controller.dart';
import 'package:mattermost_flutter/src/features/mentions/presentation/mention_strings.dart';
import 'package:mattermost_flutter/src/ui/users/widgets/user_avatar_image.dart';

/// Stateless presentation of a mention query's current suggestion state.
///
/// The composer owns focus, shortcuts and insertion; this panel only reports
/// pointer selection and highlighting back through callbacks.
final class MentionSuggestionPanel extends StatelessWidget {
  const MentionSuggestionPanel({
    required this.state,
    required this.highlightedIndex,
    required this.onSelected,
    required this.onHighlighted,
    required this.onRetry,
    required this.onDismissed,
    super.key,
  });

  final MentionAutocompleteState state;
  final int highlightedIndex;
  final ValueChanged<MentionSuggestion> onSelected;
  final ValueChanged<int> onHighlighted;
  final VoidCallback onRetry;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final MentionSearchResult? result = state.result;
    final List<MentionSuggestion> candidates =
        result?.orderedSuggestions ?? const <MentionSuggestion>[];
    return Material(
      key: const ValueKey<String>('mention-suggestion-panel'),
      color: Theme.of(context).colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320, maxWidth: 560),
        child: switch (state.status) {
          MentionAutocompleteStatus.idle => const SizedBox.shrink(),
          MentionAutocompleteStatus.loading when candidates.isEmpty =>
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
          MentionAutocompleteStatus.error when candidates.isEmpty => _Failure(
            onRetry: onRetry,
            onDismissed: onDismissed,
          ),
          MentionAutocompleteStatus.empty => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(MentionStrings.noMatches),
            ),
          ),
          _ => _SuggestionList(
            result: result!,
            highlightedIndex: highlightedIndex,
            isLoading: state.isLoading,
            hasError: state.status == MentionAutocompleteStatus.error,
            onSelected: onSelected,
            onHighlighted: onHighlighted,
            onRetry: onRetry,
          ),
        },
      ),
    );
  }
}

final class _SuggestionList extends StatelessWidget {
  const _SuggestionList({
    required this.result,
    required this.highlightedIndex,
    required this.isLoading,
    required this.hasError,
    required this.onSelected,
    required this.onHighlighted,
    required this.onRetry,
  });

  final MentionSearchResult result;
  final int highlightedIndex;
  final bool isLoading;
  final bool hasError;
  final ValueChanged<MentionSuggestion> onSelected;
  final ValueChanged<int> onHighlighted;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final List<_Entry> entries = <_Entry>[];
    var candidateIndex = 0;
    if (result.channelMembers.isNotEmpty) {
      entries.add(const _Entry.heading(MentionStrings.channelMembers));
      for (final MentionCandidate candidate in result.channelMembers) {
        entries.add(_Entry.candidate(candidate, candidateIndex++));
      }
    }
    if (result.groupMentions.isNotEmpty) {
      entries.add(const _Entry.heading(MentionStrings.groupMentions));
      for (final GroupMentionCandidate candidate in result.groupMentions) {
        entries.add(_Entry.candidate(candidate, candidateIndex++));
      }
    }
    if (result.notInChannel.isNotEmpty) {
      entries.add(const _Entry.heading(MentionStrings.notInChannel));
      for (final MentionCandidate candidate in result.notInChannel) {
        entries.add(_Entry.candidate(candidate, candidateIndex++));
      }
    }
    if (isLoading) entries.add(const _Entry.loading());
    if (hasError) entries.add(_Entry.retry(onRetry));
    return ListView.builder(
      key: const ValueKey<String>('mention-suggestion-list'),
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: entries.length,
      itemBuilder: (BuildContext context, int index) {
        final _Entry entry = entries[index];
        return switch (entry.kind) {
          _EntryKind.heading => Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              entry.label!,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          _EntryKind.loading => const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          ),
          _EntryKind.retry => TextButton(
            key: const ValueKey<String>('mention-retry-inline'),
            onPressed: entry.onRetry,
            child: const Text(MentionStrings.retry),
          ),
          _EntryKind.candidate => switch (entry.candidate!) {
            final MentionCandidate candidate => _UserCandidateTile(
              candidate: candidate,
              index: entry.candidateIndex!,
              highlighted: entry.candidateIndex == highlightedIndex,
              onSelected: onSelected,
              onHighlighted: onHighlighted,
            ),
            final GroupMentionCandidate candidate => _GroupCandidateTile(
              candidate: candidate,
              index: entry.candidateIndex!,
              highlighted: entry.candidateIndex == highlightedIndex,
              onSelected: onSelected,
              onHighlighted: onHighlighted,
            ),
          },
        };
      },
    );
  }
}

final class _UserCandidateTile extends StatelessWidget {
  const _UserCandidateTile({
    required this.candidate,
    required this.index,
    required this.highlighted,
    required this.onSelected,
    required this.onHighlighted,
  });

  final MentionCandidate candidate;
  final int index;
  final bool highlighted;
  final ValueChanged<MentionSuggestion> onSelected;
  final ValueChanged<int> onHighlighted;

  @override
  Widget build(BuildContext context) {
    final String name = candidate.user.fullName;
    final String username = candidate.user.username;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: highlighted,
      label: '$name, @$username',
      child: MouseRegion(
        onEnter: (_) => onHighlighted(index),
        child: Material(
          color: highlighted ? colors.primaryContainer : Colors.transparent,
          child: InkWell(
            key: ValueKey<String>('mention-${candidate.user.id}'),
            onTap: () => onSelected(candidate),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: <Widget>[
                  UserAvatarImage(
                    userId: candidate.user.id,
                    displayName: name,
                    profileImageUpdatedAt: candidate.user.profileImageUpdatedAt,
                    radius: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '@$username',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _GroupCandidateTile extends StatelessWidget {
  const _GroupCandidateTile({
    required this.candidate,
    required this.index,
    required this.highlighted,
    required this.onSelected,
    required this.onHighlighted,
  });

  final GroupMentionCandidate candidate;
  final int index;
  final bool highlighted;
  final ValueChanged<MentionSuggestion> onSelected;
  final ValueChanged<int> onHighlighted;

  @override
  Widget build(BuildContext context) {
    final group = candidate.group;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String count = MentionStrings.groupMemberCount(group.memberCount);
    return Semantics(
      button: true,
      selected: highlighted,
      label: '@${group.name}, ${group.displayName}, $count',
      child: MouseRegion(
        onEnter: (_) => onHighlighted(index),
        child: Material(
          color: highlighted ? colors.primaryContainer : Colors.transparent,
          child: InkWell(
            key: ValueKey<String>('mention-group-${group.id}'),
            onTap: () => onSelected(candidate),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: <Widget>[
                  SizedBox.square(
                    dimension: 36,
                    child: Icon(
                      Icons.group_outlined,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(text: '@${group.name}'),
                          TextSpan(
                            text: ' - ${group.displayName}',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          count,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _EntryKind { heading, candidate, loading, retry }

final class _Entry {
  const _Entry.heading(this.label)
    : kind = _EntryKind.heading,
      candidate = null,
      candidateIndex = null,
      onRetry = null;
  const _Entry.candidate(this.candidate, this.candidateIndex)
    : kind = _EntryKind.candidate,
      label = null,
      onRetry = null;
  const _Entry.loading()
    : kind = _EntryKind.loading,
      label = null,
      candidate = null,
      candidateIndex = null,
      onRetry = null;
  const _Entry.retry(this.onRetry)
    : kind = _EntryKind.retry,
      label = null,
      candidate = null,
      candidateIndex = null;
  final _EntryKind kind;
  final String? label;
  final MentionSuggestion? candidate;
  final int? candidateIndex;
  final VoidCallback? onRetry;
}

final class _Failure extends StatelessWidget {
  const _Failure({required this.onRetry, required this.onDismissed});
  final VoidCallback onRetry;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(MentionStrings.suggestionsFailed),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            TextButton(
              onPressed: onRetry,
              child: const Text(MentionStrings.retry),
            ),
            TextButton(
              onPressed: onDismissed,
              child: const Text(MentionStrings.dismiss),
            ),
          ],
        ),
      ],
    ),
  );
}
