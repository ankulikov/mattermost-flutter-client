import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/features/search/domain/models/message_search.dart';

/// Network-backed message search and its server-side completions.
abstract interface class MessageSearchRepository {
  Future<MessageSearchPage> search({
    required AuthSession session,
    required MessageSearchRequest request,
    Iterable<SidebarChannel> knownChannels = const <SidebarChannel>[],
  });

  Future<List<UserSearchSuggestion>> autocompleteUsers({
    required String teamId,
    required String prefix,
    int limit = 50,
  });

  Future<List<ChannelSearchSuggestion>> autocompleteChannels({
    required String teamId,
    required String prefix,
    Iterable<SidebarChannel> knownChannels = const <SidebarChannel>[],
  });
}
