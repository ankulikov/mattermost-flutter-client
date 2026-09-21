import 'dart:collection';

import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/channel_sidebar_mapper.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/message_mapper.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_repository.dart';
import 'package:mattermost_flutter/src/features/search/domain/models/message_search.dart';
import 'package:mattermost_flutter/src/features/search/domain/repositories/message_search_repository.dart';

final class MattermostMessageSearchRepository
    implements MessageSearchRepository {
  MattermostMessageSearchRepository({
    required MattermostApi api,
    required MessageMapper<MattermostPostDto, UserSummary> messageMapper,
    required UserRepository users,
    this.channelConcurrency = 4,
  }) : _api = api,
       _messageMapper = messageMapper,
       _users = users,
       assert(channelConcurrency > 0);

  final MattermostApi _api;
  final MessageMapper<MattermostPostDto, UserSummary> _messageMapper;
  final UserRepository _users;
  final int channelConcurrency;

  @override
  Future<MessageSearchPage> search({
    required AuthSession session,
    required MessageSearchRequest request,
    Iterable<SidebarChannel> knownChannels = const <SidebarChannel>[],
  }) async {
    final MattermostPostSearchDto response = await _api.searchPosts(
      teamId: request.teamId,
      request: MattermostPostSearchRequestDto(
        terms: request.terms,
        timezoneOffset: request.timezoneOffsetSeconds,
        page: request.page,
        perPage: request.perPage,
      ),
    );
    final List<MattermostPostDto> orderedPosts = response.order
        .map((String id) => response.posts[id])
        .whereType<MattermostPostDto>()
        .toList(growable: false);
    final List<UserSummary> authors = await _authorsFor(orderedPosts);
    final Map<String, SidebarChannel> channels = await _channelsFor(
      orderedPosts: orderedPosts,
      knownChannels: knownChannels,
    );
    final List<ChannelPost> posts = _messageMapper.map(
      posts: orderedPosts,
      users: authors,
      currentUserId: session.userId,
      includeDeleted: true,
    );
    final Map<String, ChannelPost> postsById = <String, ChannelPost>{
      for (final ChannelPost post in posts) post.id: post,
    };
    final List<MessageSearchResult> results = <MessageSearchResult>[];
    for (final String id in response.order) {
      final ChannelPost? post = postsById[id];
      final SidebarChannel? channel = post == null
          ? null
          : channels[post.channelId];
      if (post == null || channel == null) continue;
      results.add(
        MessageSearchResult(
          post: post,
          channel: channel,
          matches: List<String>.unmodifiable(
            response.matches[id] ?? const <String>[],
          ),
        ),
      );
    }
    return MessageSearchPage(
      results: List<MessageSearchResult>.unmodifiable(results),
      page: request.page,
      hasMore: response.order.length >= request.perPage,
      fingerprint: response.order.join('\u0000'),
    );
  }

  @override
  Future<List<UserSearchSuggestion>> autocompleteUsers({
    required String teamId,
    required String prefix,
    int limit = 50,
  }) async {
    final MattermostUserAutocompleteDto response = await _api.autocompleteUsers(
      teamId: teamId,
      channelId: '',
      name: prefix,
      limit: limit.clamp(1, 50),
    );
    return List<UserSearchSuggestion>.unmodifiable(
      response.users
          .map(_mapUser)
          .where(
            (UserSummary user) =>
                user.id.isNotEmpty && user.username.isNotEmpty,
          )
          .map(UserSearchSuggestion.new),
    );
  }

  @override
  Future<List<ChannelSearchSuggestion>> autocompleteChannels({
    required String teamId,
    required String prefix,
    Iterable<SidebarChannel> knownChannels = const <SidebarChannel>[],
  }) async {
    final List<MattermostChannelDto> remote = await _api
        .autocompleteChannelsForSearch(teamId: teamId, name: prefix);
    final String normalizedPrefix = prefix.trim().toLowerCase();
    final Map<String, SidebarChannel> channels = <String, SidebarChannel>{
      for (final SidebarChannel channel in knownChannels)
        if (_matchesChannelPrefix(channel, normalizedPrefix))
          channel.id: channel,
    };
    for (final MattermostChannelDto dto in remote) {
      try {
        channels.putIfAbsent(dto.id, () => mapChannel(dto));
      } on FormatException {
        // An invalid autocomplete row must not make the whole overlay fail.
      }
    }
    final List<SidebarChannel> sorted = channels.values.toList()
      ..sort(
        (SidebarChannel a, SidebarChannel b) =>
            a.displayName.compareTo(b.displayName),
      );
    return List<ChannelSearchSuggestion>.unmodifiable(
      sorted.map(
        (SidebarChannel channel) =>
            ChannelSearchSuggestion(channel, token: _channelToken(channel)),
      ),
    );
  }

  Future<List<UserSummary>> _authorsFor(List<MattermostPostDto> posts) async {
    final List<String> ids = posts
        .map((MattermostPostDto post) => post.userId)
        .where((String id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    return ids.isEmpty ? const <UserSummary>[] : _users.getUsers(ids);
  }

  Future<Map<String, SidebarChannel>> _channelsFor({
    required List<MattermostPostDto> orderedPosts,
    required Iterable<SidebarChannel> knownChannels,
  }) async {
    final Map<String, SidebarChannel> result = <String, SidebarChannel>{
      for (final SidebarChannel channel in knownChannels) channel.id: channel,
    };
    final List<String> missing = orderedPosts
        .map((MattermostPostDto post) => post.channelId)
        .where((String id) => id.isNotEmpty && !result.containsKey(id))
        .toSet()
        .toList(growable: false);
    final Queue<String> remaining = Queue<String>.of(missing);
    Future<void> worker() async {
      while (remaining.isNotEmpty) {
        final String id = remaining.removeFirst();
        final MattermostChannelDto dto = await _api.getChannel(id);
        result[id] = mapChannel(dto);
      }
    }

    await Future.wait<void>(
      List<Future<void>>.generate(
        missing.length < channelConcurrency
            ? missing.length
            : channelConcurrency,
        (_) => worker(),
      ),
    );
    return result;
  }
}

UserSummary _mapUser(MattermostUserDto dto) => UserSummary(
  id: dto.id,
  username: dto.username,
  firstName: dto.firstName,
  lastName: dto.lastName,
  nickname: dto.nickname,
  position: dto.position,
  email: dto.email,
  profileImageUpdatedAt: dto.lastPictureUpdate,
);

String _channelToken(SidebarChannel channel) => switch (channel.kind) {
  ChannelKind.publicChannel || ChannelKind.privateChannel => channel.name,
  ChannelKind.directMessage =>
    channel.displayName.startsWith('@')
        ? channel.displayName
        : '@${channel.displayName}',
  ChannelKind.groupMessage => channel.name.isEmpty ? channel.id : channel.name,
};

bool _matchesChannelPrefix(SidebarChannel channel, String prefix) {
  if (prefix.isEmpty) return true;
  return channel.name.toLowerCase().contains(prefix) ||
      channel.displayName.toLowerCase().contains(prefix);
}
