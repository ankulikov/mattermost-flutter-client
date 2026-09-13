import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mattermost_flutter/src/domain/models/post_navigation.dart';
import 'package:mattermost_flutter/src/ui/posts/channel_posts_strings.dart';
import 'package:mattermost_flutter/src/ui/posts/widgets/linked_post_page.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

/// One history entry for an internal Mattermost post permalink.
///
/// Only [postId] is encoded in the route location. Resolution and its
/// cancellation are owned by [postPermalinkProvider] for this route entry.
class PostPermalinkRoute extends ConsumerWidget {
  const PostPermalinkRoute({
    required this.postId,
    required this.stateScopeId,
    super.key,
  });

  static const String name = 'post-permalink';
  static const String path = '/post/:postId';

  final String postId;
  final String stateScopeId;

  static Future<void> push(BuildContext context, String postId) =>
      context.push<void>(location(postId));

  static String location(String postId) =>
      '/post/${Uri.encodeComponent(postId)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PostNavigationTarget> value = ref.watch(
      postPermalinkProvider(postId),
    );
    return value.when(
      loading: () => const _PostPermalinkLoadingPage(),
      error: (Object error, StackTrace stackTrace) => _PostPermalinkErrorPage(
        onRetry: () =>
            unawaited(ref.read(postPermalinkProvider(postId).notifier).retry()),
      ),
      data: (target) =>
          LinkedPostPage(target: target, stateScopeId: stateScopeId),
    );
  }
}

class _PostPermalinkLoadingPage extends StatelessWidget {
  const _PostPermalinkLoadingPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Semantics(
          label: ChannelPostsStrings.loadingLinkedMessage,
          child: const CircularProgressIndicator(),
        ),
      ),
    ),
  );
}

class _PostPermalinkErrorPage extends StatelessWidget {
  const _PostPermalinkErrorPage({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                ChannelPostsStrings.linkedMessageLoadFailed,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                child: const Text(ChannelPostsStrings.retry),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
