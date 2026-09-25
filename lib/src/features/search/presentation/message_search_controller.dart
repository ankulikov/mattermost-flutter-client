import 'package:flutter/foundation.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/features/search/domain/models/message_search.dart';
import 'package:mattermost_flutter/src/features/search/domain/policies/message_search_pagination.dart';
import 'package:mattermost_flutter/src/features/search/domain/policies/message_search_query.dart';
import 'package:mattermost_flutter/src/features/search/domain/repositories/message_search_repository.dart';
import 'package:mattermost_flutter/src/features/search/domain/repositories/message_search_timezone_repository.dart';

enum MessageSearchPhase { initial, initialLoading, data, initialError }

/// A shell-to-Search handoff. [nonce] makes an intent safe to observe more
/// than once while a shell rebuilds.
final class SearchLaunchIntent {
  const SearchLaunchIntent({
    required this.teamId,
    required this.initialQuery,
    required this.focus,
    required this.nonce,
  });

  final String teamId;
  final String initialQuery;
  final bool focus;
  final Object nonce;
}

final class MessageSearchViewState {
  const MessageSearchViewState({
    this.draftQuery = '',
    this.submittedQuery,
    this.phase = MessageSearchPhase.initial,
    this.results = const <MessageSearchResult>[],
    this.nextPage = 0,
    this.hasMore = false,
    this.pageFingerprints = const <String>{},
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.initialError,
    this.refreshError,
    this.paginationError,
    this.focusRequestNonce,
  });

  final String draftQuery;
  final String? submittedQuery;
  final MessageSearchPhase phase;
  final List<MessageSearchResult> results;
  final int nextPage;
  final bool hasMore;
  final Set<String> pageFingerprints;
  final bool isRefreshing;
  final bool isLoadingMore;
  final Object? initialError;
  final Object? refreshError;
  final Object? paginationError;

  /// The UI requests focus once for each consumed launch intent.
  final Object? focusRequestNonce;

  bool get hasSubmittedQuery => submittedQuery != null;

  MessageSearchViewState copyWith({
    String? draftQuery,
    Object? submittedQuery = _unset,
    MessageSearchPhase? phase,
    List<MessageSearchResult>? results,
    int? nextPage,
    bool? hasMore,
    Set<String>? pageFingerprints,
    bool? isRefreshing,
    bool? isLoadingMore,
    Object? initialError = _unset,
    Object? refreshError = _unset,
    Object? paginationError = _unset,
    Object? focusRequestNonce = _unset,
  }) => MessageSearchViewState(
    draftQuery: draftQuery ?? this.draftQuery,
    submittedQuery: identical(submittedQuery, _unset)
        ? this.submittedQuery
        : submittedQuery as String?,
    phase: phase ?? this.phase,
    results: results ?? this.results,
    nextPage: nextPage ?? this.nextPage,
    hasMore: hasMore ?? this.hasMore,
    pageFingerprints: pageFingerprints ?? this.pageFingerprints,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    initialError: identical(initialError, _unset)
        ? this.initialError
        : initialError,
    refreshError: identical(refreshError, _unset)
        ? this.refreshError
        : refreshError,
    paginationError: identical(paginationError, _unset)
        ? this.paginationError
        : paginationError,
    focusRequestNonce: identical(focusRequestNonce, _unset)
        ? this.focusRequestNonce
        : focusRequestNonce,
  );
}

const Object _unset = Object();

/// Screen-scoped, network-first state for message search.
///
/// A Riverpod auto-dispose provider owns this controller when Search UI is
/// introduced. Keeping the controller independent of provider wiring makes
/// its cancellation and context lifecycle explicit and testable.
final class MessageSearchController extends ChangeNotifier {
  MessageSearchController({
    required MessageSearchRepository repository,
    required MessageSearchTimezoneRepository timezoneRepository,
    AuthSession? session,
    String? teamId,
    Iterable<SidebarChannel> knownChannels = const <SidebarChannel>[],
    DateTime Function()? clock,
  }) : _repository = repository,
       _timezoneRepository = timezoneRepository,
       _session = session,
       _teamId = teamId,
       _knownChannels = List<SidebarChannel>.unmodifiable(knownChannels),
       _clock = clock ?? DateTime.now;

  final MessageSearchRepository _repository;
  final MessageSearchTimezoneRepository _timezoneRepository;
  final DateTime Function() _clock;
  AuthSession? _session;
  String? _teamId;
  List<SidebarChannel> _knownChannels;
  RequestCancellation? _cancellation;
  int _generation = 0;
  Object? _lastLaunchNonce;
  bool _disposed = false;
  MessageSearchViewState _state = const MessageSearchViewState();

  MessageSearchViewState get state => _state;

  void updateDraft(String value) {
    if (_disposed || value == _state.draftQuery) return;
    _setState(_state.copyWith(draftQuery: value));
  }

  /// Replaces session/team ownership. A changed account or team never shares
  /// a volatile result snapshot with its predecessor.
  void updateContext({
    required AuthSession? session,
    required String? teamId,
    Iterable<SidebarChannel> knownChannels = const <SidebarChannel>[],
  }) {
    if (_disposed) return;
    final bool changed =
        _session?.durableDataScopeId != session?.durableDataScopeId ||
        _teamId != teamId;
    _session = session;
    _teamId = teamId;
    _knownChannels = List<SidebarChannel>.unmodifiable(knownChannels);
    if (!changed) return;
    _cancelRequest();
    _lastLaunchNonce = null;
    _setState(const MessageSearchViewState());
  }

  /// Consumes a matching shell intent at most once. Existing user input wins
  /// over a late navigation intent.
  bool consumeLaunchIntent(SearchLaunchIntent intent) {
    if (_disposed ||
        intent.teamId != _teamId ||
        _lastLaunchNonce == intent.nonce) {
      return false;
    }
    _lastLaunchNonce = intent.nonce;
    if (_state.draftQuery.isNotEmpty) return false;
    _setState(
      _state.copyWith(
        draftQuery: intent.initialQuery,
        focusRequestNonce: intent.focus ? intent.nonce : null,
      ),
    );
    return true;
  }

  Future<void> submit() => _startInitialSearch(query: _state.draftQuery);

  Future<void> retry() {
    final String? query = _state.submittedQuery;
    return query == null
        ? Future<void>.value()
        : _startInitialSearch(query: query);
  }

  Future<void> refresh() async {
    final String? query = _state.submittedQuery;
    if (_disposed ||
        query == null ||
        _state.phase != MessageSearchPhase.data ||
        _state.isRefreshing ||
        _state.isLoadingMore) {
      return;
    }
    final _SearchContext? context = _context;
    if (context == null) return;
    final (RequestCancellation cancellation, int generation) = _beginRequest();
    _setState(_state.copyWith(isRefreshing: true, refreshError: null));
    try {
      final MessageSearchPage page = await _loadPage(
        context: context,
        query: query,
        page: 0,
        cancellation: cancellation,
      );
      if (!_isCurrent(cancellation, generation)) return;
      _setState(_stateFromFirstPage(query: query, page: page));
    } on Object catch (error) {
      if (!_isCurrent(cancellation, generation) ||
          error is RequestCancelledException) {
        return;
      }
      _setState(_state.copyWith(isRefreshing: false, refreshError: error));
    } finally {
      _finishRequest(cancellation);
    }
  }

  Future<void> loadMore() async {
    if (_disposed ||
        _state.phase != MessageSearchPhase.data ||
        !_state.hasMore ||
        _state.isRefreshing ||
        _state.isLoadingMore) {
      return;
    }
    final String? query = _state.submittedQuery;
    final _SearchContext? context = _context;
    if (query == null || context == null) return;
    final int pageNumber = _state.nextPage;
    final (RequestCancellation cancellation, int generation) = _beginRequest();
    _setState(_state.copyWith(isLoadingMore: true, paginationError: null));
    try {
      final MessageSearchPage page = await _loadPage(
        context: context,
        query: query,
        page: pageNumber,
        cancellation: cancellation,
      );
      if (!_isCurrent(cancellation, generation)) return;
      final MessageSearchViewState current = _state;
      if (current.pageFingerprints.contains(page.fingerprint)) {
        _setState(current.copyWith(isLoadingMore: false, hasMore: false));
        return;
      }
      final MessageSearchPage merged = mergeMessageSearchPages(
        current: MessageSearchPage(
          results: current.results,
          page: pageNumber - 1,
          hasMore: current.hasMore,
          fingerprint: current.pageFingerprints.last,
        ),
        incoming: page,
      );
      final Set<String> fingerprints = <String>{
        ...current.pageFingerprints,
        page.fingerprint,
      };
      _setState(
        current.copyWith(
          results: merged.results,
          nextPage: pageNumber + 1,
          hasMore: merged.hasMore,
          pageFingerprints: Set<String>.unmodifiable(fingerprints),
          isLoadingMore: false,
          paginationError: null,
        ),
      );
    } on Object catch (error) {
      if (!_isCurrent(cancellation, generation) ||
          error is RequestCancelledException) {
        return;
      }
      _setState(_state.copyWith(isLoadingMore: false, paginationError: error));
    } finally {
      _finishRequest(cancellation);
    }
  }

  Future<void> _startInitialSearch({required String query}) async {
    final String normalized = normalizeMessageSearchTerms(query);
    if (_disposed || !canSubmitMessageSearch(normalized)) return;
    final _SearchContext? context = _context;
    if (context == null) return;
    final (RequestCancellation cancellation, int generation) = _beginRequest();
    _setState(
      MessageSearchViewState(
        draftQuery: _state.draftQuery,
        submittedQuery: normalized,
        phase: MessageSearchPhase.initialLoading,
      ),
    );
    try {
      final MessageSearchPage page = await _loadPage(
        context: context,
        query: normalized,
        page: 0,
        cancellation: cancellation,
      );
      if (!_isCurrent(cancellation, generation)) return;
      _setState(_stateFromFirstPage(query: normalized, page: page));
    } on Object catch (error) {
      if (!_isCurrent(cancellation, generation) ||
          error is RequestCancelledException) {
        return;
      }
      _setState(
        _state.copyWith(
          phase: MessageSearchPhase.initialError,
          initialError: error,
        ),
      );
    } finally {
      _finishRequest(cancellation);
    }
  }

  MessageSearchViewState _stateFromFirstPage({
    required String query,
    required MessageSearchPage page,
  }) => MessageSearchViewState(
    draftQuery: _state.draftQuery,
    submittedQuery: query,
    phase: MessageSearchPhase.data,
    results: List<MessageSearchResult>.unmodifiable(page.results),
    nextPage: page.page + 1,
    hasMore: page.hasMore && page.results.isNotEmpty,
    pageFingerprints: Set<String>.unmodifiable(<String>{page.fingerprint}),
  );

  Future<MessageSearchPage> _loadPage({
    required _SearchContext context,
    required String query,
    required int page,
    required RequestCancellation cancellation,
  }) => cancellation.run(() async {
    final MessageSearchTimezone timezone = await _timezoneRepository.load();
    if (cancellation.isCancelled) {
      throw RequestCancelledException(cancellation.reason);
    }
    return _repository.search(
      session: context.session,
      knownChannels: context.knownChannels,
      request: MessageSearchRequest(
        teamId: context.teamId,
        terms: query,
        page: page,
        timezoneOffsetSeconds: timezone.offsetSeconds(_clock()),
      ),
    );
  });

  _SearchContext? get _context {
    final AuthSession? session = _session;
    final String? teamId = _teamId;
    if (session == null || teamId == null || teamId.isEmpty) return null;
    return _SearchContext(session, teamId, _knownChannels);
  }

  (RequestCancellation, int) _beginRequest() {
    _cancelRequest();
    final RequestCancellation cancellation = RequestCancellation();
    _cancellation = cancellation;
    return (cancellation, _generation);
  }

  bool _isCurrent(RequestCancellation cancellation, int generation) =>
      !_disposed &&
      generation == _generation &&
      identical(_cancellation, cancellation) &&
      !cancellation.isCancelled;

  void _finishRequest(RequestCancellation cancellation) {
    if (identical(_cancellation, cancellation)) _cancellation = null;
  }

  void _cancelRequest() {
    _generation += 1;
    _cancellation?.cancel();
    _cancellation = null;
  }

  void _setState(MessageSearchViewState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRequest();
    super.dispose();
  }
}

final class _SearchContext {
  const _SearchContext(this.session, this.teamId, this.knownChannels);

  final AuthSession session;
  final String teamId;
  final List<SidebarChannel> knownChannels;
}
