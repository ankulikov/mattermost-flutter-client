/// Builds the canonical web URL for a Mattermost post.
///
/// The server path is preserved for deployments hosted below a path prefix.
/// A missing team handle cannot produce a canonical Mattermost permalink.
Uri? mattermostPostPermalink({
  required Uri serverUrl,
  required String teamName,
  required String postId,
}) {
  final String normalizedTeamName = teamName.trim();
  final String normalizedPostId = postId.trim();
  if (normalizedTeamName.isEmpty || normalizedPostId.isEmpty) return null;
  return serverUrl.replace(
    pathSegments: <String>[
      ...serverUrl.pathSegments.where((String segment) => segment.isNotEmpty),
      normalizedTeamName,
      'pl',
      normalizedPostId,
    ],
    query: null,
    fragment: null,
  );
}
