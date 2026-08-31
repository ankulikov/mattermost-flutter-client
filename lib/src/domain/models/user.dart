enum UserPresence { online, away, doNotDisturb, offline }

/// A user projection suitable for author, participant, mention, and dialog
/// enrichment. It deliberately has no transport or cache representation.
class UserSummary {
  const UserSummary({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.nickname,
    required this.position,
    required this.email,
    this.profileImageUpdatedAt = 0,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String username;
  final String nickname;
  final String position;
  final String email;
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

/// A cache-bypassing profile-card projection with current presence.
final class UserProfile extends UserSummary {
  const UserProfile({
    required super.id,
    required super.firstName,
    required super.lastName,
    required super.username,
    required super.nickname,
    required super.position,
    required super.email,
    required this.presence,
    super.profileImageUpdatedAt = 0,
  });

  final UserPresence presence;
}
