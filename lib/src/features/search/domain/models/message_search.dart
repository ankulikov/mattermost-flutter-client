import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';

enum MessageSearchScopeKind { team }

final class MessageSearchRequest {
  const MessageSearchRequest({
    required this.teamId,
    required this.terms,
    required this.timezoneOffsetSeconds,
    this.scope = MessageSearchScopeKind.team,
    this.page = 0,
    this.perPage = 60,
  }) : assert(page >= 0),
       assert(perPage > 0);

  final String teamId;
  final String terms;
  final int timezoneOffsetSeconds;
  final MessageSearchScopeKind scope;
  final int page;
  final int perPage;
}

final class MessageSearchResult {
  const MessageSearchResult({
    required this.post,
    required this.channel,
    this.matches = const <String>[],
  });

  final ChannelPost post;
  final SidebarChannel channel;
  final List<String> matches;

  bool get isThreadReply => post.isReply;
}

final class MessageSearchPage {
  const MessageSearchPage({
    required this.results,
    required this.page,
    required this.hasMore,
    required this.fingerprint,
  });

  final List<MessageSearchResult> results;
  final int page;
  final bool hasMore;
  final String fingerprint;
}

sealed class SearchSuggestion {
  const SearchSuggestion();

  String get replacement;
}

final class UserSearchSuggestion extends SearchSuggestion {
  const UserSearchSuggestion(this.user);

  final UserSummary user;

  @override
  String get replacement => user.username;
}

final class ChannelSearchSuggestion extends SearchSuggestion {
  const ChannelSearchSuggestion(this.channel, {required this.token});

  final SidebarChannel channel;
  final String token;

  @override
  String get replacement => token;
}

final class DateSearchSuggestion extends SearchSuggestion {
  const DateSearchSuggestion(this.date);

  final DateTime date;

  @override
  String get replacement => _formatSearchDate(date);
}

String _formatSearchDate(DateTime date) {
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-${pad(date.month)}-${pad(date.day)}';
}

enum SearchFilterKind { from, inChannel, before, after }

extension SearchFilterKindX on SearchFilterKind {
  String get name => switch (this) {
    SearchFilterKind.from => 'from',
    SearchFilterKind.inChannel => 'in',
    SearchFilterKind.before => 'before',
    SearchFilterKind.after => 'after',
  };
}

final class ActiveSearchFilter {
  const ActiveSearchFilter({
    required this.kind,
    required this.filterStart,
    required this.valueStart,
    required this.valueEnd,
  });

  final SearchFilterKind kind;
  final int filterStart;
  final int valueStart;
  final int valueEnd;
}
