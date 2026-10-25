import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/models/mattermost_system_emojis.g.dart';
import 'package:mattermost_flutter/src/domain/policies/emoji_search.dart';
import 'package:mattermost_flutter/src/domain/repositories/emoji_repository.dart';
import 'package:mattermost_flutter/src/ui/messages/message_actions_strings.dart';

const double _pickerWidth = 500;
const double _pickerHeight = 580;
const int _customPageSize = 90;

Future<String?> showEmojiPickerPopover({
  required BuildContext context,
  required Rect anchor,
  required CustomEmojiRepository repository,
  required String accountId,
}) => showGeneralDialog<String>(
  context: context,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: Colors.black26,
  transitionDuration: const Duration(milliseconds: 120),
  pageBuilder:
      (
        BuildContext dialogContext,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          const double margin = 12;
          final double width = math.min(
            _pickerWidth,
            math.max(0, constraints.maxWidth - margin * 2),
          );
          final double height = math.min(
            _pickerHeight,
            math.max(0, constraints.maxHeight - margin * 2),
          );
          final double left = (anchor.right - width).clamp(
            margin,
            math.max(margin, constraints.maxWidth - width - margin),
          );
          final double preferredTop = anchor.bottom + 8;
          final double top = (preferredTop + height <= constraints.maxHeight)
              ? preferredTop
              : (anchor.top - height - 8).clamp(
                  margin,
                  math.max(margin, constraints.maxHeight - height - margin),
                );
          return Stack(
            children: <Widget>[
              Positioned(
                left: left,
                top: top,
                width: width,
                height: height,
                child: Card(
                  key: const ValueKey<String>('emoji-picker-popover'),
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  elevation: 8,
                  child: EmojiPicker(
                    repository: repository,
                    accountId: accountId,
                    autofocus: true,
                    onSelected: (String name) =>
                        Navigator.of(dialogContext).pop(name),
                  ),
                ),
              ),
            ],
          );
        },
      ),
);

Future<String?> showEmojiPickerBottomSheet({
  required BuildContext context,
  required CustomEmojiRepository repository,
  required String accountId,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (BuildContext sheetContext) => SizedBox(
    key: const ValueKey<String>('emoji-picker-bottom-sheet'),
    height: math.min(MediaQuery.sizeOf(sheetContext).height * 0.88, 760),
    child: EmojiPicker(
      repository: repository,
      accountId: accountId,
      onSelected: (String name) => Navigator.of(sheetContext).pop(name),
    ),
  ),
);

/// One selectable result shared by the full picker and composer autocomplete.
final class EmojiSuggestion {
  const EmojiSuggestion._({required this.name, this.unicode, this.custom});

  factory EmojiSuggestion.system(SystemEmojiDefinition emoji, {String? name}) =>
      EmojiSuggestion._(name: name ?? emoji.name, unicode: emoji.unicode);

  factory EmojiSuggestion.custom(CustomEmojiReference emoji) =>
      EmojiSuggestion._(name: emoji.name, custom: emoji);

  final String name;
  final String? unicode;
  final CustomEmojiReference? custom;
}

/// Keyboard selection state for a query-driven emoji result grid.
final class EmojiSearchNavigationController extends ChangeNotifier {
  List<EmojiSuggestion> _options = const <EmojiSuggestion>[];
  int _highlightedIndex = 0;

  int get highlightedIndex => _options.isEmpty ? -1 : _highlightedIndex;

  EmojiSuggestion? get highlightedSuggestion => _options.isEmpty
      ? null
      : _options[_highlightedIndex.clamp(0, _options.length - 1)];

  void move(int delta) {
    if (_options.isEmpty) return;
    _highlightedIndex = (_highlightedIndex + delta).clamp(
      0,
      _options.length - 1,
    );
    notifyListeners();
  }

  void highlight(int index) {
    if (index < 0 || index >= _options.length || index == _highlightedIndex) {
      return;
    }
    _highlightedIndex = index;
    notifyListeners();
  }

  void _setOptions(List<EmojiSuggestion> options) {
    final String? selectedName = highlightedSuggestion?.name;
    _options = options;
    if (options.isEmpty) {
      _highlightedIndex = 0;
    } else {
      final int retained = selectedName == null
          ? -1
          : options.indexWhere(
              (EmojiSuggestion option) => option.name == selectedName,
            );
      _highlightedIndex = retained < 0 ? 0 : retained;
    }
    notifyListeners();
  }
}

/// Emoji results controlled by an external query, without search field or
/// category navigation. Custom results are debounced and stale requests are
/// cancelled, while system results update synchronously.
class EmojiSearchResults extends StatefulWidget {
  const EmojiSearchResults({
    required this.query,
    required this.repository,
    required this.accountId,
    required this.onSelected,
    this.navigationController,
    this.limit = 200,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.onDrag,
    super.key,
  });

  final String query;
  final CustomEmojiRepository repository;
  final String accountId;
  final ValueChanged<EmojiSuggestion> onSelected;
  final EmojiSearchNavigationController? navigationController;
  final int limit;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  State<EmojiSearchResults> createState() => _EmojiSearchResultsState();
}

class _EmojiSearchResultsState extends State<EmojiSearchResults> {
  Timer? _searchDebounce;
  RequestCancellation? _searchCancellation;
  List<CustomEmojiReference> _customResults = const <CustomEmojiReference>[];
  List<EmojiSuggestion> _results = const <EmojiSuggestion>[];
  int _generation = 0;
  bool _searchingCustom = false;
  bool _customSearchFailed = false;

  @override
  void initState() {
    super.initState();
    _startSearch();
  }

  @override
  void didUpdateWidget(covariant EmojiSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationController != widget.navigationController) {
      oldWidget.navigationController?._setOptions(const <EmojiSuggestion>[]);
      widget.navigationController?._setOptions(_results);
    }
    if (oldWidget.query != widget.query ||
        oldWidget.accountId != widget.accountId ||
        oldWidget.repository != widget.repository ||
        oldWidget.limit != widget.limit) {
      _startSearch();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCancellation?.cancel('emoji search disposed');
    widget.navigationController?._setOptions(const <EmojiSuggestion>[]);
    super.dispose();
  }

  void _startSearch() {
    final String query = normalizeEmojiSearchTerm(widget.query);
    _generation += 1;
    _searchDebounce?.cancel();
    _searchCancellation?.cancel('emoji search superseded');
    _searchCancellation = null;
    _customResults = const <CustomEmojiReference>[];
    _customSearchFailed = false;
    _searchingCustom = query.length > 1;
    _updateResults(query);
    if (query.length <= 1) return;
    final int generation = _generation;
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_searchCustom(query, generation));
    });
  }

  Future<void> _searchCustom(String query, int generation) async {
    final RequestCancellation cancellation = RequestCancellation();
    _searchCancellation = cancellation;
    try {
      final List<CustomEmojiReference> values = await cancellation.run(
        () =>
            widget.repository.search(accountId: widget.accountId, term: query),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _customResults = values;
        _searchingCustom = false;
        _updateResults(query);
      });
    } on RequestCancelledException {
      // Superseded searches are expected and must not replace newer results.
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _searchingCustom = false;
        _customSearchFailed = true;
      });
    }
  }

  void _updateResults(String query) {
    final List<EmojiSuggestion> results = searchSystemEmojis(
      mattermostSystemEmojiCatalog,
      query,
      limit: widget.limit,
    ).map(EmojiSuggestion.system).toList();
    final Set<String> names = results
        .map((EmojiSuggestion option) => option.name)
        .toSet();
    for (final CustomEmojiReference emoji in _customResults) {
      if (!names.add(emoji.name)) continue;
      if (results.length >= widget.limit) results.removeLast();
      results.add(EmojiSuggestion.custom(emoji));
    }
    _results = List<EmojiSuggestion>.unmodifiable(results);
    widget.navigationController?._setOptions(_results);
  }

  @override
  Widget build(BuildContext context) {
    if (_results.isEmpty && _searchingCustom) {
      return const Center(child: CircularProgressIndicator());
    }
    final Widget grid = _results.isEmpty
        ? Center(
            child: Text(
              MessageActionsStrings.noEmojiResults(widget.query.trim()),
              textAlign: TextAlign.center,
            ),
          )
        : ListenableBuilder(
            listenable:
                widget.navigationController ?? const _NeverChangedListenable(),
            builder: (BuildContext context, Widget? child) => _EmojiGrid(
              options: _results,
              repository: widget.repository,
              accountId: widget.accountId,
              onSelected: widget.onSelected,
              keyboardDismissBehavior: widget.keyboardDismissBehavior,
              highlightedIndex:
                  widget.navigationController?.highlightedIndex ?? -1,
              onHighlight: widget.navigationController?.highlight,
            ),
          );
    return Column(
      children: <Widget>[
        if (_customSearchFailed)
          _InlineRetry(
            message: MessageActionsStrings.customEmojiSearchFailed,
            onRetry: () => _searchCustom(
              normalizeEmojiSearchTerm(widget.query),
              _generation,
            ),
          )
        else if (_searchingCustom)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(child: grid),
      ],
    );
  }
}

class _NeverChangedListenable implements Listenable {
  const _NeverChangedListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

class EmojiPicker extends StatefulWidget {
  const EmojiPicker({
    required this.repository,
    required this.accountId,
    required this.onSelected,
    this.autofocus = false,
    super.key,
  });

  final CustomEmojiRepository repository;
  final String accountId;
  final ValueChanged<String> onSelected;
  final bool autofocus;

  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker> {
  late final TextEditingController _searchController = TextEditingController()
    ..addListener(_searchChanged);
  final RequestCancellation _pageCancellation = RequestCancellation();
  List<String> _recentNames = const <String>[];
  List<CustomEmojiReference> _customEmojis = const <CustomEmojiReference>[];
  String _selectedCategory = 'recent';
  String _query = '';
  int _nextCustomPage = 0;
  bool _loadingRecents = true;
  bool _loadingCustom = false;
  bool _customLoadFailed = false;
  bool _hasMoreCustom = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecents());
  }

  @override
  void dispose() {
    _pageCancellation.cancel('emoji picker disposed');
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    try {
      final List<String> values = await widget.repository.getRecent(
        accountId: widget.accountId,
      );
      if (!mounted) return;
      setState(() {
        _recentNames = values;
        _loadingRecents = false;
        if (values.isEmpty && _selectedCategory == 'recent') {
          _selectedCategory = 'smileys-emotion';
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loadingRecents = false;
        _selectedCategory = 'smileys-emotion';
      });
    }
  }

  void _searchChanged() {
    final String query = normalizeEmojiSearchTerm(_searchController.text);
    if (query == _query) return;
    setState(() => _query = query);
  }

  Future<void> _loadMoreCustom() async {
    if (_loadingCustom || !_hasMoreCustom) return;
    setState(() {
      _loadingCustom = true;
      _customLoadFailed = false;
    });
    try {
      final List<CustomEmojiReference> page = await _pageCancellation.run(
        () => widget.repository.getPage(
          accountId: widget.accountId,
          page: _nextCustomPage,
          perPage: _customPageSize,
        ),
      );
      if (!mounted) return;
      final Map<String, CustomEmojiReference> merged =
          <String, CustomEmojiReference>{
            for (final CustomEmojiReference emoji in _customEmojis)
              emoji.name: emoji,
            for (final CustomEmojiReference emoji in page) emoji.name: emoji,
          };
      setState(() {
        _customEmojis = List<CustomEmojiReference>.unmodifiable(merged.values);
        _nextCustomPage += 1;
        _hasMoreCustom = page.length == _customPageSize;
        _loadingCustom = false;
      });
    } on RequestCancelledException {
      // Picker disposal cancels an in-flight page.
    } on Object {
      if (!mounted) return;
      setState(() {
        _loadingCustom = false;
        _customLoadFailed = true;
      });
    }
  }

  void _selectCategory(String category) {
    setState(() => _selectedCategory = category);
    if (category == 'custom' && _customEmojis.isEmpty) {
      unawaited(_loadMoreCustom());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: SearchBar(
              key: const ValueKey<String>('emoji-search-field'),
              controller: _searchController,
              autoFocus: widget.autofocus,
              hintText: MessageActionsStrings.searchEmojis,
              leading: const Icon(Icons.search),
              trailing: <Widget>[
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).deleteButtonTooltip,
                    onPressed: _searchController.clear,
                    icon: const Icon(Icons.close),
                  ),
              ],
              textInputAction: TextInputAction.search,
            ),
          ),
          if (_query.isEmpty)
            _CategoryBar(
              selected: _selectedCategory,
              showsRecent: _recentNames.isNotEmpty || _loadingRecents,
              onSelected: _selectCategory,
            ),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_query.isNotEmpty) {
      return EmojiSearchResults(
        query: _query,
        repository: widget.repository,
        accountId: widget.accountId,
        onSelected: (EmojiSuggestion suggestion) =>
            widget.onSelected(suggestion.name),
      );
    }

    if (_selectedCategory == 'recent' && _loadingRecents) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_selectedCategory == 'custom') {
      return Column(
        children: <Widget>[
          if (_customLoadFailed)
            _InlineRetry(
              message: MessageActionsStrings.customEmojiLoadFailed,
              onRetry: _loadMoreCustom,
            ),
          Expanded(
            child: _EmojiGrid(
              options: _customEmojis
                  .map(EmojiSuggestion.custom)
                  .toList(growable: false),
              repository: widget.repository,
              accountId: widget.accountId,
              onSelected: (EmojiSuggestion suggestion) =>
                  widget.onSelected(suggestion.name),
              hasMore: _hasMoreCustom && !_customLoadFailed,
              isLoadingMore: _loadingCustom,
              onLoadMore: _loadMoreCustom,
            ),
          ),
        ],
      );
    }

    final List<EmojiSuggestion> options = _selectedCategory == 'recent'
        ? _recentOptions()
        : mattermostSystemEmojiCatalog
              .where(
                (SystemEmojiDefinition emoji) =>
                    emoji.category == _selectedCategory &&
                    !emoji.name.contains('_skin_tone'),
              )
              .map(EmojiSuggestion.system)
              .toList(growable: false);
    return _EmojiGrid(
      options: options,
      repository: widget.repository,
      accountId: widget.accountId,
      onSelected: (EmojiSuggestion suggestion) =>
          widget.onSelected(suggestion.name),
    );
  }

  List<EmojiSuggestion> _recentOptions() => _recentNames
      .map((String name) {
        final SystemEmojiDefinition? system = _systemEmojiByAlias[name];
        if (system != null) return EmojiSuggestion.system(system, name: name);
        final CustomEmojiReference custom = _customEmojis.firstWhere(
          (CustomEmojiReference emoji) => emoji.name == name,
          orElse: () => CustomEmojiReference(name: name),
        );
        return EmojiSuggestion.custom(custom);
      })
      .toList(growable: false);
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.selected,
    required this.showsRecent,
    required this.onSelected,
  });

  final String selected;
  final bool showsRecent;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: <Widget>[
        for (final _EmojiCategory category in _emojiCategories)
          if (category.key != 'recent' || showsRecent)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: IconButton(
                key: ValueKey<String>('emoji-category-${category.key}'),
                tooltip: category.label,
                isSelected: selected == category.key,
                style: IconButton.styleFrom(
                  backgroundColor: selected == category.key
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                ),
                onPressed: () => onSelected(category.key),
                icon: Icon(category.icon),
              ),
            ),
      ],
    ),
  );
}

class _EmojiGrid extends StatelessWidget {
  const _EmojiGrid({
    required this.options,
    required this.repository,
    required this.accountId,
    required this.onSelected,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.onLoadMore,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.onDrag,
    this.highlightedIndex = -1,
    this.onHighlight,
  });

  final List<EmojiSuggestion> options;
  final CustomEmojiRepository repository;
  final String accountId;
  final ValueChanged<EmojiSuggestion> onSelected;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback? onLoadMore;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;
  final int highlightedIndex;
  final ValueChanged<int>? onHighlight;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty && !hasMore && !isLoadingMore) {
      return const Center(child: Text(MessageActionsStrings.noEmojis));
    }
    final int itemCount = options.length + (hasMore || isLoadingMore ? 1 : 0);
    return GridView.builder(
      key: const ValueKey<String>('emoji-grid'),
      padding: const EdgeInsets.all(12),
      keyboardDismissBehavior: keyboardDismissBehavior,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 58,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: itemCount,
      itemBuilder: (BuildContext context, int index) {
        if (index == options.length) {
          if (!isLoadingMore) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => onLoadMore?.call(),
            );
          }
          return const Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        final EmojiSuggestion option = options[index];
        return Tooltip(
          message: ':${option.name}:',
          child: Semantics(
            button: true,
            label: ':${option.name}:',
            selected: index == highlightedIndex,
            child: MouseRegion(
              onEnter: (_) => onHighlight?.call(index),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: index == highlightedIndex
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: InkResponse(
                  key: ValueKey<String>('emoji-${option.name}'),
                  radius: 24,
                  onTap: () => onSelected(option),
                  child: Center(
                    child: option.custom == null
                        ? Text(
                            option.unicode!,
                            style: const TextStyle(fontSize: 28),
                          )
                        : CustomEmojiImage(
                            repository: repository,
                            accountId: accountId,
                            emoji: option.custom!,
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class CustomEmojiImage extends StatefulWidget {
  const CustomEmojiImage({
    required this.repository,
    required this.accountId,
    required this.emoji,
    super.key,
  });

  final CustomEmojiRepository repository;
  final String accountId;
  final CustomEmojiReference emoji;

  @override
  State<CustomEmojiImage> createState() => _CustomEmojiImageState();
}

class _CustomEmojiImageState extends State<CustomEmojiImage> {
  late Future<CustomEmojiContent> _content = _load();

  Future<CustomEmojiContent> _load() => widget.repository.getByName(
    accountId: widget.accountId,
    name: widget.emoji.name,
    emojiId: widget.emoji.id,
    updatedAt: widget.emoji.updatedAt,
  );

  @override
  void didUpdateWidget(covariant CustomEmojiImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        oldWidget.emoji != widget.emoji) {
      _content = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CustomEmojiContent>(
    future: _content,
    builder:
        (BuildContext context, AsyncSnapshot<CustomEmojiContent> snapshot) {
          final CustomEmojiContent? content = snapshot.data;
          if (content == null) {
            return snapshot.hasError
                ? const Icon(Icons.broken_image_outlined, size: 24)
                : const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
          }
          return Image.memory(
            content.bytes,
            width: 32,
            height: 32,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.broken_image_outlined, size: 24),
          );
        },
  );
}

class _InlineRetry extends StatelessWidget {
  const _InlineRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MaterialBanner(
    content: Text(message),
    actions: <Widget>[
      TextButton(
        onPressed: onRetry,
        child: const Text(MessageActionsStrings.retry),
      ),
    ],
  );
}

final Map<String, SystemEmojiDefinition> _systemEmojiByAlias =
    <String, SystemEmojiDefinition>{
      for (final SystemEmojiDefinition emoji in mattermostSystemEmojiCatalog)
        for (final String alias in emoji.aliases) alias: emoji,
    };

final class _EmojiCategory {
  const _EmojiCategory(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

const List<_EmojiCategory> _emojiCategories = <_EmojiCategory>[
  _EmojiCategory('recent', MessageActionsStrings.recentlyUsed, Icons.history),
  _EmojiCategory(
    'smileys-emotion',
    MessageActionsStrings.smileysAndEmotion,
    Icons.emoji_emotions_outlined,
  ),
  _EmojiCategory(
    'people-body',
    MessageActionsStrings.peopleAndBody,
    Icons.person_outline,
  ),
  _EmojiCategory(
    'animals-nature',
    MessageActionsStrings.animalsAndNature,
    Icons.eco_outlined,
  ),
  _EmojiCategory(
    'food-drink',
    MessageActionsStrings.foodAndDrink,
    Icons.apple_outlined,
  ),
  _EmojiCategory(
    'travel-places',
    MessageActionsStrings.travelAndPlaces,
    Icons.flight_outlined,
  ),
  _EmojiCategory(
    'activities',
    MessageActionsStrings.activities,
    Icons.sports_basketball_outlined,
  ),
  _EmojiCategory(
    'objects',
    MessageActionsStrings.objects,
    Icons.lightbulb_outline,
  ),
  _EmojiCategory(
    'symbols',
    MessageActionsStrings.symbols,
    Icons.favorite_border,
  ),
  _EmojiCategory('flags', MessageActionsStrings.flags, Icons.flag_outlined),
  _EmojiCategory(
    'custom',
    MessageActionsStrings.customEmoji,
    Icons.add_reaction_outlined,
  ),
];
