/// Mattermost user display-name policy shared by every feature.
String resolveUserDisplayName({
  required String id,
  required String username,
  required String nickname,
  required String firstName,
  required String lastName,
}) {
  final String fullName = <String>[firstName, lastName]
      .map((String value) => value.trim())
      .where((String value) => value.isNotEmpty)
      .join(' ');
  if (fullName.isNotEmpty) return fullName;
  if (nickname.trim().isNotEmpty) return nickname.trim();
  if (username.trim().isNotEmpty) return username.trim();
  return id;
}
