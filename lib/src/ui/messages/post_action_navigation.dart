import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/ui/messages/mattermost_markdown.dart';
import 'package:mattermost_flutter/src/ui/messages/rich_attachment_strings.dart';
import 'package:mattermost_flutter/src/ui/posts/post_permalink_route.dart';
import 'package:url_launcher/url_launcher.dart';

/// Navigates only to safe destinations returned by Mattermost after an action.
Future<void> handlePostActionGotoLocation(
  BuildContext context, {
  required Uri? serverUrl,
  required String location,
}) async {
  final Uri? parsed = Uri.tryParse(location);
  final Uri? resolved = parsed == null
      ? null
      : parsed.scheme.isEmpty
      ? serverUrl?.resolveUri(parsed)
      : parsed;
  final String? postId = resolved == null || serverUrl == null
      ? null
      : mattermostPostIdFromPermalink(uri: resolved, serverUrl: serverUrl);
  if (postId != null) {
    await PostPermalinkRoute.push(context, postId);
    return;
  }
  if (resolved == null ||
      !const <String>{
        'http',
        'https',
      }.contains(resolved.scheme.toLowerCase())) {
    _showError(context);
    return;
  }
  try {
    if (!await launchUrl(resolved) && context.mounted) _showError(context);
  } on Object {
    if (context.mounted) _showError(context);
  }
}

void _showError(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(content: Text(RichAttachmentStrings.navigationFailed)),
  );
}
