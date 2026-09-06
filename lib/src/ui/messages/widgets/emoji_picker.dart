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
  Timer? _searchDebounce;
  RequestCancellation? _searchCancellation;
  List<String> _recentNames = const <String>[];
  List<CustomEmojiReference> _customEmojis = const <CustomEmojiReference>[];
  List<CustomEmojiReference> _customSearch = const <CustomEmojiReference>[];
  String _selectedCategory = 'recent';
  String _query = '';
  int _searchGeneration = 0;
  int _nextCustomPage = 0;
  bool _loadingRecents = true;
  bool _loadingCustom = false;
  bool _searchingCustom = false;
  bool _customLoadFailed = false;
  bool _customSearchFailed = false;
  bool _hasMoreCustom = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecents());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCancellation?.cancel('emoji search superseded');
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
    _query = query;
    _searchGeneration += 1;
    _searchDebounce?.cancel();
    _searchCancellation?.cancel('emoji search superseded');
    _searchCancellation = null;
    setState(() {
      _customSearch = const <CustomEmojiReference>[];
      _customSearchFailed = false;
      _searchingCustom = query.length > 1;
    });
    if (query.length <= 1) return;
    final int generation = _searchGeneration;
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
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _customSearch = values;
        _searchingCustom = false;
      });
    } on RequestCancelledException {
      // Superseded searches are expected and must not replace newer results.
    } on Object {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchingCustom = false;
        _customSearchFailed = true;
      });
    }
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
      final List<_EmojiOption> results = _searchResults();
      if (results.isEmpty && _searchingCustom) {
        return const Center(child: CircularProgressIndicator());
      }
      return Column(
        children: <Widget>[
          if (_customSearchFailed)
            _InlineRetry(
              message: MessageActionsStrings.customEmojiSearchFailed,
              onRetry: () => _searchCustom(_query, _searchGeneration),
            )
          else if (_searchingCustom)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Text(
                      MessageActionsStrings.noEmojiResults(
                        _searchController.text.trim(),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _EmojiGrid(
                    options: results,
                    repository: widget.repository,
                    accountId: widget.accountId,
                    onSelected: widget.onSelected,
                  ),
          ),
        ],
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
                  .map(_EmojiOption.custom)
                  .toList(growable: false),
              repository: widget.repository,
              accountId: widget.accountId,
              onSelected: widget.onSelected,
              hasMore: _hasMoreCustom && !_customLoadFailed,
              isLoadingMore: _loadingCustom,
              onLoadMore: _loadMoreCustom,
            ),
          ),
        ],
      );
    }

    final List<_EmojiOption> options = _selectedCategory == 'recent'
        ? _recentOptions()
        : mattermostSystemEmojiCatalog
              .where(
                (SystemEmojiDefinition emoji) =>
                    emoji.category == _selectedCategory &&
                    !emoji.name.contains('_skin_tone'),
              )
              .map(_EmojiOption.system)
              .toList(growable: false);
    return _EmojiGrid(
      options: options,
      repository: widget.repository,
      accountId: widget.accountId,
      onSelected: widget.onSelected,
    );
  }

  List<_EmojiOption> _searchResults() {
    final List<_EmojiOption> results = searchSystemEmojis(
      mattermostSystemEmojiCatalog,
      _query,
    ).map(_EmojiOption.system).toList();
    final Set<String> names = results
        .map((_EmojiOption option) => option.name)
        .toSet();
    for (final CustomEmojiReference emoji in _customSearch) {
      if (names.add(emoji.name)) results.add(_EmojiOption.custom(emoji));
    }
    return results;
  }

  List<_EmojiOption> _recentOptions() => _recentNames
      .map((String name) {
        final SystemEmojiDefinition? system = _systemEmojiByAlias[name];
        if (system != null) return _EmojiOption.system(system, name: name);
        final CustomEmojiReference custom = _customEmojis.firstWhere(
          (CustomEmojiReference emoji) => emoji.name == name,
          orElse: () => CustomEmojiReference(name: name),
        );
        return _EmojiOption.custom(custom);
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
  });

  final List<_EmojiOption> options;
  final CustomEmojiRepository repository;
  final String accountId;
  final ValueChanged<String> onSelected;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty && !hasMore && !isLoadingMore) {
      return const Center(child: Text(MessageActionsStrings.noEmojis));
    }
    final int itemCount = options.length + (hasMore || isLoadingMore ? 1 : 0);
    return GridView.builder(
      key: const ValueKey<String>('emoji-grid'),
      padding: const EdgeInsets.all(12),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
        final _EmojiOption option = options[index];
        return Tooltip(
          message: ':${option.name}:',
          child: Semantics(
            button: true,
            label: ':${option.name}:',
            child: InkResponse(
              key: ValueKey<String>('emoji-${option.name}'),
              radius: 24,
              onTap: () => onSelected(option.name),
              child: Center(
                child: option.custom == null
                    ? Text(
                        option.unicode!,
                        style: const TextStyle(fontSize: 28),
                      )
                    : _CustomEmojiImage(
                        repository: repository,
                        accountId: accountId,
                        emoji: option.custom!,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CustomEmojiImage extends StatefulWidget {
  const _CustomEmojiImage({
    required this.repository,
    required this.accountId,
    required this.emoji,
  });

  final CustomEmojiRepository repository;
  final String accountId;
  final CustomEmojiReference emoji;

  @override
  State<_CustomEmojiImage> createState() => _CustomEmojiImageState();
}

class _CustomEmojiImageState extends State<_CustomEmojiImage> {
  late Future<CustomEmojiContent> _content = _load();

  Future<CustomEmojiContent> _load() => widget.repository.getByName(
    accountId: widget.accountId,
    name: widget.emoji.name,
    emojiId: widget.emoji.id,
    updatedAt: widget.emoji.updatedAt,
  );

  @override
  void didUpdateWidget(covariant _CustomEmojiImage oldWidget) {
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

final class _EmojiOption {
  const _EmojiOption._({required this.name, this.unicode, this.custom});

  factory _EmojiOption.system(SystemEmojiDefinition emoji, {String? name}) =>
      _EmojiOption._(name: name ?? emoji.name, unicode: emoji.unicode);

  factory _EmojiOption.custom(CustomEmojiReference emoji) =>
      _EmojiOption._(name: emoji.name, custom: emoji);

  final String name;
  final String? unicode;
  final CustomEmojiReference? custom;
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
