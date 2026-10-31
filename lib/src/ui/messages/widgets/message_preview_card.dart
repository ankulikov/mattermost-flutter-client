import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_content.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';

/// The shared message card surface used by Inbox and thread summaries.
///
/// Feature-specific details and actions remain outside this widget so callers
/// can reuse the same message presentation without inheriting Inbox behavior.
class MessagePreviewCard extends StatelessWidget {
  const MessagePreviewCard({
    required this.interactionKey,
    required this.header,
    required this.post,
    required this.onTap,
    this.serverUrl,
    this.headerKey,
    this.details,
    this.actions,
    this.selected = false,
    super.key,
  });

  final Key interactionKey;
  final String header;
  final Post post;
  final VoidCallback onTap;
  final Uri? serverUrl;
  final Key? headerKey;
  final Widget? details;
  final Widget? actions;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: selected ? theme.colorScheme.secondaryContainer : null,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          key: interactionKey,
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    MessageAvatar(author: post.author),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            header,
                            key: headerKey,
                            style: theme.textTheme.labelLarge,
                          ),
                          _AuthorLine(author: post.author, sentAt: post.sentAt),
                          const SizedBox(height: 6),
                          MessageContent(
                            post: post,
                            serverUrl: serverUrl,
                            enableTextSelection: false,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (details case final Widget details) ...<Widget>[
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                details,
              ],
              if (actions case final Widget actions) ...<Widget>[
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                actions,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthorLine extends StatelessWidget {
  const _AuthorLine({required this.author, required this.sentAt});

  final PostAuthor author;
  final DateTime sentAt;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          author.displayName,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          formatMessageTimestamp(
            sentAt: sentAt,
            locale: Localizations.localeOf(context).toLanguageTag(),
          ),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
