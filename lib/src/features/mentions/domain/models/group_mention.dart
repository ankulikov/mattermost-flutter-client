/// A referenceable Mattermost user group.
///
/// [name] is the canonical at-mention handle. It is intentionally also the
/// visible label: unlike user mentions, group mentions are never rewritten to
/// their display name.
final class GroupMention {
  const GroupMention({
    required this.id,
    required this.name,
    required this.displayName,
    required this.memberCount,
  });

  final String id;
  final String name;
  final String displayName;
  final int memberCount;
}
