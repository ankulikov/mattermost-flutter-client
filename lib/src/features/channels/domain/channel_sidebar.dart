enum ChannelKind { publicChannel, privateChannel, directMessage, groupMessage }

enum ChannelSorting { manual, recent }

final class SidebarTeam {
  const SidebarTeam({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

final class SidebarChannel {
  const SidebarChannel({
    required this.id,
    required this.teamId,
    required this.name,
    required this.displayName,
    required this.kind,
    this.lastActivityAt = 0,
  });

  final String id;
  final String teamId;
  final String name;
  final String displayName;
  final ChannelKind kind;
  final int lastActivityAt;

  bool get isDialog =>
      kind == ChannelKind.directMessage || kind == ChannelKind.groupMessage;

  SidebarChannel withDisplayName(String value) => SidebarChannel(
    id: id,
    teamId: teamId,
    name: name,
    displayName: value,
    kind: kind,
    lastActivityAt: lastActivityAt,
  );
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
    this.isRefreshing = false,
    this.refreshFailed = false,
  });

  final SidebarTeam? team;
  final List<SidebarSection> sections;
  final bool isRefreshing;
  final bool refreshFailed;

  bool get hasData => team != null || sections.isNotEmpty;

  ChannelSidebarSnapshot copyWith({
    SidebarTeam? team,
    List<SidebarSection>? sections,
    bool? isRefreshing,
    bool? refreshFailed,
  }) => ChannelSidebarSnapshot(
    team: team ?? this.team,
    sections: sections ?? this.sections,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    refreshFailed: refreshFailed ?? this.refreshFailed,
  );
}
