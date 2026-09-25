import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/features/search/domain/models/message_search.dart';
import 'package:mattermost_flutter/src/features/search/domain/policies/message_search_query.dart';
import 'package:mattermost_flutter/src/features/search/domain/repositories/message_search_repository.dart';

enum MessageSearchSuggestionStatus { idle, loading, data, empty, error }

final class MessageSearchSuggestionState {
  const MessageSearchSuggestionState({
    this.activeFilter,
    this.prefix = '',
    this.status = MessageSearchSuggestionStatus.idle,
    this.suggestions = const <SearchSuggestion>[],
    this.error,
  });

  final ActiveSearchFilter? activeFilter;
  final String prefix;
  final MessageSearchSuggestionStatus status;
  final List<SearchSuggestion> suggestions;
  final Object? error;

  bool get showsCalendar =>
      activeFilter?.kind == SearchFilterKind.before ||
      activeFilter?.kind == SearchFilterKind.after;
}

/// Foreground-only completion state for a Search query field.
final class MessageSearchSuggestionsController extends ChangeNotifier {
  MessageSearchSuggestionsController({
    required MessageSearchRepository repository,
    required this.teamId,
    this.knownChannels = const <SidebarChannel>[],
    this.debounce = const Duration(milliseconds: 200),
  }) : _repository = repository;

  final MessageSearchRepository _repository;
  final String teamId;
  final Iterable<SidebarChannel> knownChannels;
  final Duration debounce;

  Timer? _timer;
  RequestCancellation? _cancellation;
  int _generation = 0;
  bool _disposed = false;
  MessageSearchSuggestionState _state = const MessageSearchSuggestionState();

  MessageSearchSuggestionState get state => _state;

  void update({required String query, required int caretOffset}) {
    if (_disposed) return;
    final ActiveSearchFilter? active = activeMessageSearchFilter(
      query,
      caretOffset,
    );
    _cancelPending();
    if (active == null) {
      _setState(const MessageSearchSuggestionState());
      return;
    }
    if (active.kind == SearchFilterKind.before ||
        active.kind == SearchFilterKind.after) {
      _setState(MessageSearchSuggestionState(activeFilter: active));
      return;
    }
    final int caret = caretOffset.clamp(active.valueStart, active.valueEnd);
    final String prefix = query.substring(active.valueStart, caret);
    _setState(
      MessageSearchSuggestionState(
        activeFilter: active,
        prefix: prefix,
        status: MessageSearchSuggestionStatus.loading,
      ),
    );
    final int generation = _generation;
    _timer = Timer(debounce, () {
      if (_disposed || generation != _generation) return;
      unawaited(_load(active, prefix, generation));
    });
  }

  void retry() {
    final ActiveSearchFilter? active = _state.activeFilter;
    if (_disposed ||
        active == null ||
        active.kind == SearchFilterKind.before ||
        active.kind == SearchFilterKind.after) {
      return;
    }
    _cancelPending();
    _setState(
      MessageSearchSuggestionState(
        activeFilter: active,
        prefix: _state.prefix,
        status: MessageSearchSuggestionStatus.loading,
      ),
    );
    unawaited(_load(active, _state.prefix, _generation));
  }

  String insert({
    required String query,
    required int caretOffset,
    required SearchSuggestion suggestion,
  }) => insertMessageSearchSuggestion(
    query: query,
    caretOffset: caretOffset,
    replacement: suggestion.replacement,
  );

  String insertDate({
    required String query,
    required int caretOffset,
    required DateTime date,
  }) => insertMessageSearchSuggestion(
    query: query,
    caretOffset: caretOffset,
    replacement: formatMessageSearchDate(date),
  );

  Future<void> _load(
    ActiveSearchFilter active,
    String prefix,
    int generation,
  ) async {
    final RequestCancellation cancellation = RequestCancellation();
    _cancellation = cancellation;
    try {
      final List<SearchSuggestion> suggestions = await cancellation.run(
        () async {
          return switch (active.kind) {
            SearchFilterKind.from => await _repository.autocompleteUsers(
              teamId: teamId,
              prefix: prefix,
            ),
            SearchFilterKind.inChannel =>
              await _repository.autocompleteChannels(
                teamId: teamId,
                prefix: prefix,
                knownChannels: knownChannels,
              ),
            SearchFilterKind.before ||
            SearchFilterKind.after => const <SearchSuggestion>[],
          };
        },
      );
      if (!_isCurrent(cancellation, generation)) return;
      _setState(
        MessageSearchSuggestionState(
          activeFilter: active,
          prefix: prefix,
          suggestions: List<SearchSuggestion>.unmodifiable(suggestions),
          status: suggestions.isEmpty
              ? MessageSearchSuggestionStatus.empty
              : MessageSearchSuggestionStatus.data,
        ),
      );
    } on Object catch (error) {
      if (!_isCurrent(cancellation, generation) ||
          error is RequestCancelledException) {
        return;
      }
      _setState(
        MessageSearchSuggestionState(
          activeFilter: active,
          prefix: prefix,
          status: MessageSearchSuggestionStatus.error,
          error: error,
        ),
      );
    } finally {
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  void _setState(MessageSearchSuggestionState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  bool _isCurrent(RequestCancellation cancellation, int generation) =>
      !_disposed &&
      generation == _generation &&
      identical(_cancellation, cancellation) &&
      !cancellation.isCancelled;

  void _cancelPending() {
    _generation += 1;
    _timer?.cancel();
    _timer = null;
    _cancellation?.cancel();
    _cancellation = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelPending();
    super.dispose();
  }
}
