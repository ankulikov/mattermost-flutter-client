import 'dart:collection';

enum PostponedReferenceKind { post, thread }

/// The durable, content-free reference stored in Mattermost preferences.
final class PostponedReference {
  const PostponedReference({
    required this.postId,
    required this.kind,
    required this.addedAt,
    this.targetPostId,
  });

  /// A post id, or the root post id for a thread reference.
  final String postId;
  final PostponedReferenceKind kind;
  final DateTime addedAt;
  final String? targetPostId;

  String get canonicalId => postId;
}

/// References read from preferences before their post previews are hydrated.
final class PostponedReferencesSnapshot {
  PostponedReferencesSnapshot(Iterable<PostponedReference> references)
    : references = UnmodifiableListView<PostponedReference>(
        references.toList(),
      );

  final List<PostponedReference> references;
}
