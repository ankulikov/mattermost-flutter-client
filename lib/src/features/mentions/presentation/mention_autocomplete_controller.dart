import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/mention_query.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_candidate.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_search_result.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/repositories/mention_repository.dart';

enum MentionAutocompleteStatus { idle, loading, data, empty, error }

/// Immutable, foreground-only state for the active composer mention query.
final class MentionAutocompleteState {
  const MentionAutocompleteState({
    this.query,
    this.status = MentionAutocompleteStatus.idle,
    this.result,
    this.error,
  });

  final MentionQuery? query;
  final MentionAutocompleteStatus status;
  final MentionSearchResult? result;
  final Object? error;

  bool get isLoading => status == MentionAutocompleteStatus.loading;
  bool get hasResults => result != null && !_isEmpty(result!);

  MentionAutocompleteState copyWith({
    MentionQuery? query,
    MentionAutocompleteStatus? status,
    MentionSearchResult? result,
    Object? error,
    bool clearQuery = false,
    bool clearResult = false,
    bool clearError = false,
  }) => MentionAutocompleteState(
    query: clearQuery ? null : (query ?? this.query),
    status: status ?? this.status,
    result: clearResult ? null : (result ?? this.result),
    error: clearError ? null : (error ?? this.error),
  );
}

/// Keyboard highlight state decoupled from the query/result lifecycle.
final class MentionSuggestionNavigationController extends ChangeNotifier {
  List<MentionCandidate> _options = const <MentionCandidate>[];
  int _highlightedIndex = 0;

  int get highlightedIndex => _options.isEmpty ? -1 : _highlightedIndex;
  MentionCandidate? get highlightedCandidate => _options.isEmpty
      ? null
      : _options[_highlightedIndex.clamp(0, _options.length - 1)];

  void move(int delta) {
    if (_options.isEmpty) return;
    final int next = (_highlightedIndex + delta).clamp(0, _options.length - 1);
    if (next == _highlightedIndex) return;
    _highlightedIndex = next;
    notifyListeners();
  }

  void highlight(int index) {
    if (index < 0 || index >= _options.length || index == _highlightedIndex) {
      return;
    }
    _highlightedIndex = index;
    notifyListeners();
  }

  void setOptions(List<MentionCandidate> options) {
    final String? previousId = highlightedCandidate?.user.id;
    _options = List<MentionCandidate>.unmodifiable(options);
    final int retained = previousId == null
        ? -1
        : _options.indexWhere(
            (MentionCandidate candidate) => candidate.user.id == previousId,
          );
    _highlightedIndex = retained < 0 ? 0 : retained;
    notifyListeners();
  }
}

/// Debounced network search for mention suggestions.
///
/// Results are kept only for this controller's lifetime. A newer query cancels
/// infrastructure that honors [RequestCancellation.current] and independently
/// guards against stale completions.
final class MentionAutocompleteController extends ChangeNotifier {
  MentionAutocompleteController({
    required MentionRepository repository,
    required this.teamId,
    required this.channelId,
    this.limit = 100,
    this.debounce = const Duration(milliseconds: 200),
  }) : _repository = repository;

  final MentionRepository _repository;
  final String teamId;
  final String channelId;
  final int limit;
  final Duration debounce;
  final Map<String, MentionSearchResult> _cache =
      <String, MentionSearchResult>{};
  Timer? _debounce;
  RequestCancellation? _cancellation;
  var _generation = 0;
  var _disposed = false;
  MentionAutocompleteState _state = const MentionAutocompleteState();

  MentionAutocompleteState get state => _state;

  void updateQuery(MentionQuery? query) {
    if (_disposed) return;
    final MentionQuery? previous = _state.query;
    if (query == null) {
      _cancelPending();
      _setState(const MentionAutocompleteState());
      return;
    }
    if (previous?.key == query.key && previous?.trigger == query.trigger) {
      _setState(_state.copyWith(query: query));
      return;
    }
    _start(query, debounced: true);
  }

  void retry() {
    final MentionQuery? query = _state.query;
    if (_disposed || query == null) return;
    _start(query, debounced: false, bypassCache: true);
  }

  void dismiss() {
    if (_disposed) return;
    _cancelPending();
    _setState(const MentionAutocompleteState());
  }

  void _start(
    MentionQuery query, {
    required bool debounced,
    bool bypassCache = false,
  }) {
    _cancelPending();
    final String cacheKey = _cacheKey(query.key);
    final MentionSearchResult? cached = bypassCache ? null : _cache[cacheKey];
    if (cached != null) {
      _setState(
        MentionAutocompleteState(
          query: query,
          result: cached,
          status: _isEmpty(cached)
              ? MentionAutocompleteStatus.empty
              : MentionAutocompleteStatus.data,
        ),
      );
      return;
    }

    _setState(
      MentionAutocompleteState(
        query: query,
        result: _state.result,
        status: MentionAutocompleteStatus.loading,
      ),
    );
    final int generation = _generation;
    void begin() {
      if (_disposed || generation != _generation) return;
      unawaited(_search(query, generation));
    }

    if (debounced) {
      _debounce = Timer(debounce, begin);
    } else {
      begin();
    }
  }

  Future<void> _search(MentionQuery query, int generation) async {
    final RequestCancellation cancellation = RequestCancellation();
    _cancellation = cancellation;
    try {
      final MentionSearchResult result = await cancellation.run(
        () => _repository.autocomplete(
          teamId: teamId,
          channelId: channelId,
          term: query.term,
          limit: limit,
        ),
      );
      if (!_isCurrent(cancellation, generation)) return;
      _cache[_cacheKey(query.key)] = result;
      _setState(
        MentionAutocompleteState(
          query: query,
          result: result,
          status: _isEmpty(result)
              ? MentionAutocompleteStatus.empty
              : MentionAutocompleteStatus.data,
        ),
      );
    } catch (error) {
      if (!_isCurrent(cancellation, generation) ||
          error is RequestCancelledException) {
        return;
      }
      _setState(
        MentionAutocompleteState(
          query: query,
          result: _state.result,
          status: MentionAutocompleteStatus.error,
          error: error,
        ),
      );
    } finally {
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  bool _isCurrent(RequestCancellation cancellation, int generation) =>
      !_disposed &&
      generation == _generation &&
      identical(cancellation, _cancellation) &&
      !cancellation.isCancelled;

  void _cancelPending() {
    _generation += 1;
    _debounce?.cancel();
    _debounce = null;
    _cancellation?.cancel();
    _cancellation = null;
  }

  String _cacheKey(String key) => '$teamId\u0000$channelId\u0000$key';

  void _setState(MentionAutocompleteState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelPending();
    super.dispose();
  }
}

bool _isEmpty(MentionSearchResult result) =>
    result.channelMembers.isEmpty && result.notInChannel.isEmpty;
