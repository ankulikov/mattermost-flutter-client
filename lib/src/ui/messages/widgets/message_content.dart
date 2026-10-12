import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_attachments.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/rich_attachments.dart';

/// The shared post content stack for channel, thread, and linked-post views.
class MessageContent extends StatelessWidget {
  const MessageContent({
    required this.post,
    this.serverUrl,
    this.onSelectChannel,
    this.onOpenPostLink,
    this.onQuoteSelection,
    this.deletedMessage,
    this.onRichAttachmentAction,
    this.actionScopeId,
    this.onRichAttachmentPostUpdated,
    this.onRichAttachmentGotoLocation,
    this.enableTextSelection = true,
    super.key,
  });

  final ChannelPost post;
  final Uri? serverUrl;
  final ValueChanged<String>? onSelectChannel;
  final ValueChanged<String>? onOpenPostLink;
  final ValueChanged<String>? onQuoteSelection;
  final String? deletedMessage;
  final RichAttachmentActionCallback? onRichAttachmentAction;
  final String? actionScopeId;
  final ValueChanged<ChannelPost>? onRichAttachmentPostUpdated;
  final ValueChanged<String>? onRichAttachmentGotoLocation;
  final bool enableTextSelection;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      MessageBody(
        post: post,
        serverUrl: serverUrl,
        onSelectChannel: onSelectChannel,
        onOpenPostLink: onOpenPostLink,
        onQuoteSelection: onQuoteSelection,
        deletedMessage: deletedMessage,
        enableTextSelection: enableTextSelection,
      ),
      if (!post.isDeleted && post.richAttachments.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        RichAttachments(
          attachments: post.richAttachments,
          customEmojis: post.customEmojis,
          serverUrl: serverUrl,
          onSelectChannel: onSelectChannel,
          onOpenPostLink: onOpenPostLink,
          onAction: onRichAttachmentAction,
          postId: post.id,
          channelId: post.channelId,
          sourceRootPostId: post.rootId.isEmpty ? post.id : post.rootId,
          actionScopeId: actionScopeId,
          onPostUpdated: onRichAttachmentPostUpdated,
          onGotoLocation: onRichAttachmentGotoLocation,
          enableTextSelection: enableTextSelection,
        ),
      ],
      if (!post.isDeleted && post.attachments.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        MessageAttachments(attachments: post.attachments),
      ],
    ],
  );
}
