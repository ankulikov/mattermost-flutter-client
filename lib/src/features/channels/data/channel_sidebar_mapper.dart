import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';

SidebarTeam mapTeam(MattermostTeamDto dto) => SidebarTeam(
  id: _required(dto.id, 'team.id'),
  displayName: dto.displayName.trim().isNotEmpty
      ? dto.displayName.trim()
      : _required(dto.name, 'team.name'),
);

SidebarChannel mapChannel(MattermostChannelDto dto) {
  final String type = _required(dto.type, 'channel.type');
  final ChannelKind kind = switch (type) {
    'O' => ChannelKind.publicChannel,
    'P' => ChannelKind.privateChannel,
    'D' => ChannelKind.directMessage,
    'G' => ChannelKind.groupMessage,
    _ => throw FormatException('Unsupported Mattermost channel type: $type'),
  };
  final String name = _required(dto.name, 'channel.name');
  return SidebarChannel(
    id: _required(dto.id, 'channel.id'),
    teamId: dto.teamId,
    name: name,
    displayName: dto.displayName.trim().isNotEmpty
        ? dto.displayName.trim()
        : name,
    kind: kind,
  );
}

List<SidebarSection> mapSections({
  required List<SidebarChannel> channels,
  required List<MattermostChannelCategoryDto> categories,
  required List<String> categoryOrder,
}) {
  final Map<String, SidebarChannel> byId = <String, SidebarChannel>{
    for (final SidebarChannel channel in channels) channel.id: channel,
  };
  final Set<String> assigned = <String>{};
  final List<SidebarSection> sections = <SidebarSection>[];
  final Map<String, MattermostChannelCategoryDto> categoriesById =
      <String, MattermostChannelCategoryDto>{
        for (final MattermostChannelCategoryDto category in categories)
          category.id: category,
      };
  final Set<String> orderedCategoryIds = <String>{};
  final List<MattermostChannelCategoryDto> orderedCategories =
      <MattermostChannelCategoryDto>[];
  for (final String categoryId in categoryOrder) {
    if (!orderedCategoryIds.add(categoryId)) continue;
    final MattermostChannelCategoryDto? category = categoriesById[categoryId];
    if (category != null) orderedCategories.add(category);
  }
  for (final MattermostChannelCategoryDto category in categories) {
    if (orderedCategoryIds.add(category.id)) orderedCategories.add(category);
  }

  for (final MattermostChannelCategoryDto category in orderedCategories) {
    final List<SidebarChannel> categoryChannels = category.channelIds
        .map((String id) => byId[id])
        .whereType<SidebarChannel>()
        .toList(growable: false);
    if (categoryChannels.isEmpty) continue;
    assigned.addAll(categoryChannels.map((SidebarChannel item) => item.id));
    sections.add(
      SidebarSection(
        id: _required(category.id, 'category.id'),
        displayName: _categoryDisplayName(category),
        channels: categoryChannels,
      ),
    );
  }

  final List<SidebarChannel> remaining = channels
      .where((SidebarChannel channel) => !assigned.contains(channel.id))
      .toList(growable: false);
  final List<SidebarChannel> regular = remaining
      .where((SidebarChannel channel) => !channel.isDialog)
      .toList(growable: false);
  final List<SidebarChannel> dialogs = remaining
      .where((SidebarChannel channel) => channel.isDialog)
      .toList(growable: false);
  if (regular.isNotEmpty) {
    sections.add(
      SidebarSection(
        id: 'uncategorized-channels',
        displayName: 'Channels',
        channels: regular,
      ),
    );
  }
  if (dialogs.isNotEmpty) {
    sections.add(
      SidebarSection(
        id: 'uncategorized-dialogs',
        displayName: 'Direct messages',
        channels: dialogs,
      ),
    );
  }
  return List<SidebarSection>.unmodifiable(sections);
}

String userDisplayName(MattermostUserDto user) {
  final String fullName = <String>[user.firstName, user.lastName]
      .map((String value) => value.trim())
      .where((String value) => value.isNotEmpty)
      .join(' ');
  if (fullName.isNotEmpty) return fullName;
  return _required(user.username, 'user.username');
}

String _categoryDisplayName(MattermostChannelCategoryDto dto) {
  if (dto.displayName.trim().isNotEmpty) {
    return dto.displayName.trim();
  }
  return switch (dto.type) {
    'favorites' => 'Favorites',
    'direct_messages' => 'Direct messages',
    _ => 'Channels',
  };
}

String _required(String value, String path) {
  if (value.isNotEmpty) return value;
  throw FormatException('Expected non-empty string at $path');
}
