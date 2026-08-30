enum UserPresence { online, away, doNotDisturb, offline }

final class UserProfile {
  const UserProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.nickname,
    required this.position,
    required this.email,
    required this.presence,
    this.profileImageUpdatedAt = 0,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String username;
  final String nickname;
  final String position;
  final String email;
  final UserPresence presence;
  final int profileImageUpdatedAt;

  String get fullName {
    final String value = <String>[
      firstName,
      lastName,
    ].where((String part) => part.trim().isNotEmpty).join(' ').trim();
    if (value.isNotEmpty) return value;
    if (nickname.trim().isNotEmpty) return nickname.trim();
    return username.trim().isEmpty ? id : username.trim();
  }

  String get handle {
    final String value = nickname.trim().isEmpty
        ? username.trim()
        : nickname.trim();
    return value.isEmpty ? id : value;
  }
}
