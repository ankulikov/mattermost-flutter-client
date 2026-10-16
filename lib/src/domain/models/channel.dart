enum ChannelKind { publicChannel, privateChannel, directMessage, groupMessage }

enum ChannelSorting { manual, recent }

final class SidebarTeam {
  const SidebarTeam({
    required this.id,
    required this.displayName,
    this.name = '',
  });

  final String id;
  final String displayName;

  /// URL-safe Mattermost team handle used in browser permalinks.
  final String name;
}

final class SidebarChannel {
  const SidebarChannel({
    required this.id,
    required this.teamId,
    required this.name,
    required this.displayName,
    required this.kind,
    this.teamName = '',
    this.lastActivityAt = 0,
    this.profileImage,
    this.isUnread = false,
    this.muted = false,
  });

  final String id;
  final String teamId;
  final String name;
  final String displayName;
  final ChannelKind kind;

  /// URL-safe Mattermost team handle used in browser permalinks.
  final String teamName;
  final int lastActivityAt;
  final SidebarProfileImage? profileImage;
  final bool isUnread;
  final bool muted;

  bool get isDialog =>
      kind == ChannelKind.directMessage || kind == ChannelKind.groupMessage;

  SidebarChannel withDisplayName(String value) => SidebarChannel(
    id: id,
    teamId: teamId,
    name: name,
    displayName: value,
    kind: kind,
    teamName: teamName,
    lastActivityAt: lastActivityAt,
    profileImage: profileImage,
    isUnread: isUnread,
    muted: muted,
  );

  SidebarChannel withDirectUser({
    required String displayName,
    required String userId,
    required int profileImageUpdatedAt,
  }) => SidebarChannel(
    id: id,
    teamId: teamId,
    name: name,
    displayName: displayName,
    kind: kind,
    teamName: teamName,
    lastActivityAt: lastActivityAt,
    profileImage: SidebarProfileImage(
      userId: userId,
      updatedAt: profileImageUpdatedAt,
    ),
    isUnread: isUnread,
    muted: muted,
  );

  SidebarChannel copyWith({bool? isUnread, bool? muted}) => SidebarChannel(
    id: id,
    teamId: teamId,
    name: name,
    displayName: displayName,
    kind: kind,
    teamName: teamName,
    lastActivityAt: lastActivityAt,
    profileImage: profileImage,
    isUnread: isUnread ?? this.isUnread,
    muted: muted ?? this.muted,
  );
}

/// Versioned reference to a direct-message participant's profile image.
///
/// Image bytes remain owned by the user repository. A sidebar snapshot carries
/// only the data needed to start an asynchronous image request.
final class SidebarProfileImage {
  const SidebarProfileImage({required this.userId, required this.updatedAt});

  final String userId;
  final int updatedAt;
}

final class SidebarSection {
  const SidebarSection({
    required this.id,
    required this.displayName,
    required this.channels,
    this.collapsed = false,
    this.muted = false,
    this.sorting = ChannelSorting.manual,
  });

  final String id;
  final String displayName;
  final List<SidebarChannel> channels;
  final bool collapsed;
  final bool muted;
  final ChannelSorting sorting;
}

final class ChannelSidebarSnapshot {
  const ChannelSidebarSnapshot({
    this.team,
    this.sections = const <SidebarSection>[],
  });

  final SidebarTeam? team;
  final List<SidebarSection> sections;

  bool get hasData => team != null || sections.isNotEmpty;

  ChannelSidebarSnapshot copyWith({
    SidebarTeam? team,
    List<SidebarSection>? sections,
  }) => ChannelSidebarSnapshot(
    team: team ?? this.team,
    sections: sections ?? this.sections,
  );
}
