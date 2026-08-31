String avatarInitials(String displayName) => displayName
    .trim()
    .split(RegExp(r'\s+'))
    .where((String part) => part.isNotEmpty)
    .take(2)
    .map((String part) => part[0].toUpperCase())
    .join();
