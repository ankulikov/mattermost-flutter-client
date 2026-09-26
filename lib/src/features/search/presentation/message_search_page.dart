import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/search/domain/models/message_search.dart';
import 'package:mattermost_flutter/src/features/search/domain/policies/message_search_query.dart';
import 'package:mattermost_flutter/src/features/search/presentation/message_search_controller.dart';
import 'package:mattermost_flutter/src/features/search/presentation/message_search_suggestions_controller.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_content.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_primitives.dart';
import 'package:mattermost_flutter/src/ui/posts/post_permalink_route.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

abstract final class MessageSearchStrings {
  static const String title = 'Search';
  static const String hint = 'Search messages';
  static const String syntax = 'Use words or filters to search messages.';
  static const String from = 'From';
  static const String inChannel = 'In';
  static const String before = 'Before';
  static const String after = 'After';
  static const String noResults = 'No messages found.';
  static const String searchFailed = 'Could not search messages.';
  static const String retry = 'Retry';
  static const String refresh = 'Refresh';
  static const String loadMore = 'Load more';
  static const String loading = 'Searching messages';
  static const String threadIn = 'Thread in';
  static const String suggestionsFailed = 'Could not load suggestions.';
}

final messageSearchControllerProvider =
    Provider.autoDispose<MessageSearchController>((Ref ref) {
      final AuthSession? session = ref.watch(authSessionProvider);
      final ChannelSidebarSnapshot? snapshot = ref
          .watch(channelSidebarProvider)
          .value
          ?.snapshot;
      final String? teamId = snapshot?.team?.id;
      final List<SidebarChannel> channels = snapshot == null
          ? const <SidebarChannel>[]
          : snapshot.sections
                .expand((SidebarSection section) => section.channels)
                .toList(growable: false);
      final MessageSearchController controller = MessageSearchController(
        repository: ref.watch(messageSearchRepositoryProvider),
        timezoneRepository: ref.watch(messageSearchTimezoneRepositoryProvider),
        session: session,
        teamId: teamId,
        knownChannels: channels,
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

final messageSearchSuggestionsProvider =
    Provider.autoDispose<MessageSearchSuggestionsController>((Ref ref) {
      final ChannelSidebarSnapshot? snapshot = ref
          .watch(channelSidebarProvider)
          .value
          ?.snapshot;
      final String teamId = snapshot?.team?.id ?? '';
      final List<SidebarChannel> channels = snapshot == null
          ? const <SidebarChannel>[]
          : snapshot.sections
                .expand((SidebarSection section) => section.channels)
                .toList(growable: false);
      final MessageSearchSuggestionsController controller =
          MessageSearchSuggestionsController(
            repository: ref.watch(messageSearchRepositoryProvider),
            teamId: teamId,
            knownChannels: channels,
          );
      ref.onDispose(controller.dispose);
      return controller;
    });

class MessageSearchPage extends ConsumerStatefulWidget {
  const MessageSearchPage({this.launchIntent, super.key});

  final SearchLaunchIntent? launchIntent;

  @override
  ConsumerState<MessageSearchPage> createState() => _MessageSearchPageState();
}

class _MessageSearchPageState extends ConsumerState<MessageSearchPage> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final ScrollController _scrollController;
  late final MessageSearchController _searchController;
  late final MessageSearchSuggestionsController _suggestionsController;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _searchController = ref.read(messageSearchControllerProvider)
      ..addListener(_rebuild);
    _suggestionsController = ref.read(messageSearchSuggestionsProvider)
      ..addListener(_rebuild);
    _scrollController = ScrollController()..addListener(_loadMoreWhenNeeded);
    _textController.addListener(_onTextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _consumeIntent();
  }

  @override
  void didUpdateWidget(covariant MessageSearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _consumeIntent();
  }

  @override
  void dispose() {
    _searchController.removeListener(_rebuild);
    _suggestionsController.removeListener(_rebuild);
    _textController
      ..removeListener(_onTextChanged)
      ..dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _consumeIntent() {
    final SearchLaunchIntent? intent = widget.launchIntent;
    if (intent == null) return;
    final MessageSearchController controller = ref.read(
      messageSearchControllerProvider,
    );
    if (!controller.consumeLaunchIntent(intent)) return;
    _syncText(controller.state.draftQuery, focus: intent.focus);
  }

  void _onTextChanged() {
    if (_syncing) return;
    final MessageSearchController controller = ref.read(
      messageSearchControllerProvider,
    );
    controller.updateDraft(_textController.text);
    ref
        .read(messageSearchSuggestionsProvider)
        .update(
          query: _textController.text,
          caretOffset: _textController.selection.extentOffset,
        );
  }

  void _syncText(String text, {bool focus = false}) {
    if (_textController.text != text) {
      _syncing = true;
      _textController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _syncing = false;
    }
    if (focus) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusNode.requestFocus(),
      );
    }
  }

  void _loadMoreWhenNeeded() {
    if (_scrollController.position.extentAfter < 240) {
      unawaited(ref.read(messageSearchControllerProvider).loadMore());
    }
  }

  void _insertFilter(SearchFilterKind kind) {
    final String query = insertMessageSearchFilterPrefix(
      query: _textController.text,
      caretOffset: _textController.selection.extentOffset,
      kind: kind,
    );
    _syncText(query, focus: true);
    ref.read(messageSearchControllerProvider).updateDraft(query);
    ref
        .read(messageSearchSuggestionsProvider)
        .update(query: query, caretOffset: query.length);
  }

  Future<void> _selectDate(
    MessageSearchSuggestionsController suggestions,
  ) async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10),
      initialDate: now,
    );
    if (date == null || !mounted) return;
    final String query = suggestions.insertDate(
      query: _textController.text,
      caretOffset: _textController.selection.extentOffset,
      date: date,
    );
    _syncText(query, focus: true);
    ref.read(messageSearchControllerProvider).updateDraft(query);
  }

  @override
  Widget build(BuildContext context) {
    final MessageSearchController controller = ref.watch(
      messageSearchControllerProvider,
    );
    final MessageSearchViewState state = controller.state;
    final MessageSearchSuggestionsController suggestions = ref.watch(
      messageSearchSuggestionsProvider,
    );
    if (_textController.text != state.draftQuery) _syncText(state.draftQuery);
    return Scaffold(
      appBar: AppBar(
        title: const Text(MessageSearchStrings.title),
        actions: <Widget>[
          IconButton(
            tooltip: MessageSearchStrings.refresh,
            onPressed: state.phase is MessageSearchData
                ? () => unawaited(controller.refresh())
                : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                key: const ValueKey<String>('message-search-field'),
                controller: _textController,
                focusNode: _focusNode,
                selectAllOnFocus: false,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => unawaited(controller.submit()),
                onTap: () => suggestions.update(
                  query: _textController.text,
                  caretOffset: _textController.selection.extentOffset,
                ),
                decoration: InputDecoration(
                  hintText: MessageSearchStrings.hint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _textController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).deleteButtonTooltip,
                          icon: const Icon(Icons.clear),
                          onPressed: () => _syncText('', focus: true),
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            _FilterChips(onSelected: _insertFilter),
            ListenableBuilder(
              listenable: suggestions,
              builder: (BuildContext context, Widget? child) => _Suggestions(
                controller: suggestions,
                onSelect: (SearchSuggestion suggestion) {
                  final String query = suggestions.insert(
                    query: _textController.text,
                    caretOffset: _textController.selection.extentOffset,
                    suggestion: suggestion,
                  );
                  _syncText(query, focus: true);
                  ref.read(messageSearchControllerProvider).updateDraft(query);
                },
                onSelectDate: () => _selectDate(suggestions),
              ),
            ),
            Expanded(
              child: _Results(
                state: state,
                controller: controller,
                scrollController: _scrollController,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.onSelected});
  final ValueChanged<SearchFilterKind> onSelected;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: <Widget>[
        _chip(MessageSearchStrings.from, SearchFilterKind.from),
        _chip(MessageSearchStrings.inChannel, SearchFilterKind.inChannel),
        _chip(MessageSearchStrings.before, SearchFilterKind.before),
        _chip(MessageSearchStrings.after, SearchFilterKind.after),
      ],
    ),
  );
  Widget _chip(String label, SearchFilterKind kind) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: ActionChip(label: Text(label), onPressed: () => onSelected(kind)),
  );
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.controller,
    required this.onSelect,
    required this.onSelectDate,
  });
  final MessageSearchSuggestionsController controller;
  final ValueChanged<SearchSuggestion> onSelect;
  final VoidCallback onSelectDate;
  @override
  Widget build(BuildContext context) {
    final MessageSearchSuggestionState state = controller.state;
    if (state.showsCalendar) {
      return ListTile(
        key: const ValueKey<String>('message-search-calendar'),
        leading: const Icon(Icons.calendar_today),
        title: const Text('Choose date'),
        onTap: onSelectDate,
      );
    }
    if (state.status == MessageSearchSuggestionStatus.idle) {
      return const SizedBox.shrink();
    }
    if (state.status == MessageSearchSuggestionStatus.loading) {
      return const LinearProgressIndicator();
    }
    if (state.status == MessageSearchSuggestionStatus.error) {
      return ListTile(
        title: const Text(MessageSearchStrings.suggestionsFailed),
        trailing: TextButton(
          onPressed: controller.retry,
          child: const Text(MessageSearchStrings.retry),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: state.suggestions.length,
        itemBuilder: (BuildContext context, int index) {
          final SearchSuggestion suggestion = state.suggestions[index];
          final (
            String title,
            String subtitle,
            IconData icon,
          ) = switch (suggestion) {
            UserSearchSuggestion(:final UserSummary user) => (
              user.fullName,
              '@${user.username}',
              Icons.person_outline,
            ),
            ChannelSearchSuggestion(
              :final SidebarChannel channel,
              :final String token,
            ) =>
              (
                channel.displayName,
                'in:$token',
                channel.isDialog ? Icons.person_outline : Icons.tag,
              ),
            DateSearchSuggestion(:final DateTime date) => (
              formatMessageSearchDate(date),
              '',
              Icons.calendar_today,
            ),
          };
          return ListTile(
            key: ValueKey<String>('message-search-suggestion-$index'),
            leading: Icon(icon),
            title: Text(title),
            subtitle: subtitle.isEmpty ? null : Text(subtitle),
            onTap: () => onSelect(suggestion),
          );
        },
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.state,
    required this.controller,
    required this.scrollController,
  });
  final MessageSearchViewState state;
  final MessageSearchController controller;
  final ScrollController scrollController;
  @override
  Widget build(BuildContext context) {
    if (state.phase is MessageSearchInitialLoading) {
      return Center(
        child: Semantics(
          label: MessageSearchStrings.loading,
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (state.phase is MessageSearchInitialFailure) {
      return _Centered(
        message: MessageSearchStrings.searchFailed,
        action: () => unawaited(controller.retry()),
      );
    }
    if (state.phase is MessageSearchInitial) {
      return const _Centered(message: MessageSearchStrings.syntax);
    }
    if (state.results.isEmpty) {
      return const _Centered(message: MessageSearchStrings.noResults);
    }
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.builder(
        controller: scrollController,
        itemCount: state.results.length + 1,
        itemBuilder: (BuildContext context, int index) {
          if (index == state.results.length) {
            return _Pagination(state: state, controller: controller);
          }
          return _ResultTile(result: state.results[index]);
        },
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.message, this.action});
  final String message;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(message, textAlign: TextAlign.center),
        if (action != null)
          TextButton(
            onPressed: action,
            child: const Text(MessageSearchStrings.retry),
          ),
      ],
    ),
  );
}

class _Pagination extends StatelessWidget {
  const _Pagination({required this.state, required this.controller});
  final MessageSearchViewState state;
  final MessageSearchController controller;
  @override
  Widget build(BuildContext context) {
    if (state.paginationStatus is OperationInProgress) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.paginationStatus is OperationFailed) {
      return Center(
        child: TextButton(
          onPressed: () => unawaited(controller.loadMore()),
          child: const Text(MessageSearchStrings.retry),
        ),
      );
    }
    if (!state.hasMore) return const SizedBox(height: 24);
    return Center(
      child: TextButton(
        onPressed: () => unawaited(controller.loadMore()),
        child: const Text(MessageSearchStrings.loadMore),
      ),
    );
  }
}

class _ResultTile extends StatefulWidget {
  const _ResultTile({required this.result});
  final MessageSearchResult result;

  @override
  State<_ResultTile> createState() => _ResultTileState();
}

class _ResultTileState extends State<_ResultTile> {
  bool _hovered = false;

  void _setHovered(bool hovered) {
    if (_hovered != hovered) setState(() => _hovered = hovered);
  }

  void _openResult() {
    unawaited(PostPermalinkRoute.push(context, widget.result.post.id));
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    onTap: _openResult,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openResult,
        child: AnimatedContainer(
          key: ValueKey<String>(
            'message-search-result-${widget.result.post.id}',
          ),
          duration: const Duration(milliseconds: 180),
          color: _hovered
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MessageAvatar(author: widget.result.post.author),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.result.isThreadReply
                            ? '${MessageSearchStrings.threadIn} ${widget.result.channel.displayName}'
                            : widget.result.channel.displayName,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      MessageAuthorLine(
                        author: widget.result.post.author,
                        sentAt: widget.result.post.sentAt,
                      ),
                      const SizedBox(height: 5),
                      MessageContent(post: widget.result.post),
                      if (widget.result.matches.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 4,
                            children: widget.result.matches
                                .map((String match) => Chip(label: Text(match)))
                                .toList(growable: false),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
