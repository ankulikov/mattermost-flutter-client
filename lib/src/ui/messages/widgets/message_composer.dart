import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/repositories/emoji_repository.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_breakpoints.dart';
import 'package:mattermost_flutter/src/ui/messages/message_composer_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/message_editor_controller.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/emoji_picker.dart';

typedef SubmitMessage =
    Future<void> Function(String message, String pendingPostId);

/// Shared text-only composer for channel posts and thread replies.
class MessageComposer extends StatefulWidget {
  const MessageComposer({
    required this.destinationId,
    required this.placeholder,
    required this.onSubmit,
    this.emojiRepositoryFactory,
    this.accountId = '',
    super.key,
  });

  final String destinationId;
  final String placeholder;
  final SubmitMessage onSubmit;
  final CustomEmojiRepository Function()? emojiRepositoryFactory;
  final String accountId;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  late final MessageEditorController _controller;
  late final FocusNode _focusNode;
  final EmojiSearchNavigationController _emojiNavigation =
      EmojiSearchNavigationController();
  final Object _textFieldTapGroup = Object();
  CustomEmojiRepository? _emojiRepository;
  bool _sending = false;
  bool _failed = false;
  String? _pendingPostId;
  String? _pendingDraft;
  String? _dismissedEmojiQuery;

  bool get _canSend => !_sending && _controller.messageText.trim().isNotEmpty;

  CustomEmojiRepository? get _availableEmojiRepository {
    final CustomEmojiRepository Function()? factory =
        widget.emojiRepositoryFactory;
    if (factory == null || widget.accountId.isEmpty) return null;
    return _emojiRepository ??= factory();
  }

  EmojiAutocompleteQuery? get _visibleEmojiQuery {
    if (_sending || !_focusNode.hasFocus) return null;
    final EmojiAutocompleteQuery? query = _controller.emojiAutocompleteQuery;
    if (query == null ||
        _emojiQueryKey(query) == _dismissedEmojiQuery ||
        widget.emojiRepositoryFactory == null ||
        widget.accountId.isEmpty) {
      return null;
    }
    return query;
  }

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_onFocusChanged);
    _controller = MessageEditorController(
      customEmojiBuilder: (BuildContext context, CustomEmojiReference emoji) {
        final CustomEmojiRepository? repository = _availableEmojiRepository;
        if (repository == null) return Text(':${emoji.name}:');
        return CustomEmojiImage(
          key: ValueKey<String>('composer-custom-emoji-${emoji.name}'),
          repository: repository,
          accountId: widget.accountId,
          emoji: emoji,
        );
      },
    )..addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destinationId != widget.destinationId) {
      _controller.clear();
      _pendingPostId = null;
      _pendingDraft = null;
      _failed = false;
    }
    if (oldWidget.accountId != widget.accountId) {
      _emojiRepository = null;
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    _emojiNavigation.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_pendingDraft != null && _controller.text != _pendingDraft) {
      _pendingPostId = null;
      _pendingDraft = null;
      _failed = false;
    }
    final EmojiAutocompleteQuery? query = _controller.emojiAutocompleteQuery;
    if (query == null || _emojiQueryKey(query) != _dismissedEmojiQuery) {
      _dismissedEmojiQuery = null;
    }
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  String _emojiQueryKey(EmojiAutocompleteQuery query) =>
      '${query.range.start}:${query.term}';

  Future<void> _submit({bool finalizeComposing = false}) async {
    if (!_canSend) return;
    final TextEditingValue value = _controller.value;
    if (value.composing.isValid && !value.composing.isCollapsed) {
      if (!finalizeComposing) return;
      // Android keyboards such as Gboard keep the word at the caret in a
      // composing region for autocorrect. An explicit send action finalizes
      // that word; it must not silently discard the tap while the IME is open.
      _controller.clearComposing();
    }

    final String message = _controller.messageText;
    final String draft = _controller.text;
    final String pendingPostId =
        _pendingPostId ??
        'flutter:${DateTime.now().microsecondsSinceEpoch}:${widget.destinationId}';
    _pendingPostId = pendingPostId;
    _pendingDraft = draft;
    setState(() {
      _sending = true;
      _failed = false;
    });
    try {
      await widget.onSubmit(message, pendingPostId);
      if (!mounted) return;
      if (_controller.text == draft) _controller.clear();
      _pendingPostId = null;
      _pendingDraft = null;
      _focusNode.unfocus();
    } on Object {
      if (!mounted) return;
      setState(() => _failed = true);
      _focusNode.requestFocus();
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _insertNewLine() {
    if (_sending) return;
    final TextEditingValue value = _controller.value;
    final TextSelection selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final String text = value.text.replaceRange(
      selection.start,
      selection.end,
      '\n',
    );
    _controller.value = value.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: selection.start + 1),
      composing: TextRange.empty,
    );
  }

  void _submitOrSelectEmoji() {
    final EmojiSuggestion? suggestion = _visibleEmojiQuery == null
        ? null
        : _emojiNavigation.highlightedSuggestion;
    if (suggestion != null) {
      _selectEmoji(suggestion);
      return;
    }
    unawaited(_submit());
  }

  void _selectEmoji(EmojiSuggestion suggestion) {
    final EmojiAutocompleteQuery? query = _controller.emojiAutocompleteQuery;
    if (query == null) return;
    final CustomEmojiReference? custom = suggestion.custom;
    if (custom == null) {
      _controller.replaceQueryWithUnicode(query, suggestion.unicode!);
    } else {
      _controller.replaceQueryWithCustomEmoji(query, custom);
    }
    _dismissedEmojiQuery = null;
    _focusNode.requestFocus();
    final CustomEmojiRepository? repository = _availableEmojiRepository;
    if (repository != null) {
      unawaited(_rememberEmoji(repository, suggestion.name));
    }
  }

  Future<void> _rememberEmoji(
    CustomEmojiRepository repository,
    String name,
  ) async {
    try {
      await repository.rememberRecent(
        accountId: widget.accountId,
        emojiName: name,
      );
    } on Object {
      // MRU persistence must never interrupt composing a message.
    }
  }

  void _dismissEmojiAutocomplete() {
    final EmojiAutocompleteQuery? query = _controller.emojiAutocompleteQuery;
    if (query == null) return;
    setState(() => _dismissedEmojiQuery = _emojiQueryKey(query));
  }

  void _copySelection({required bool cut}) {
    final TextSelection selection = _controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    unawaited(_copySelectionToClipboard(selection, cut: cut));
  }

  Future<void> _copySelectionToClipboard(
    TextSelection selection, {
    required bool cut,
  }) async {
    try {
      await Clipboard.setData(
        ClipboardData(
          text: _controller.messageTextForRange(
            TextRange(start: selection.start, end: selection.end),
          ),
        ),
      );
      if (cut && mounted && _controller.selection == selection) {
        _controller.replaceSelectionWithText('');
      }
    } on Object {
      // Clipboard availability is platform-owned and must not break the draft.
    }
  }

  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final List<ContextMenuButtonItem> items = editableTextState
        .contextMenuButtonItems
        .map(
          (ContextMenuButtonItem item) => switch (item.type) {
            ContextMenuButtonType.copy => item.copyWith(
              onPressed: () {
                ContextMenuController.removeAny();
                _copySelection(cut: false);
              },
            ),
            ContextMenuButtonType.cut => item.copyWith(
              onPressed: () {
                ContextMenuController.removeAny();
                _copySelection(cut: true);
              },
            ),
            _ => item,
          },
        )
        .toList(growable: false);
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final EmojiAutocompleteQuery? emojiQuery = _visibleEmojiQuery;
    final CustomEmojiRepository? emojiRepository = emojiQuery == null
        ? null
        : _availableEmojiRepository;
    return Semantics(
      container: true,
      label: widget.placeholder,
      child: Padding(
        key: ValueKey<String>('message-composer-${widget.destinationId}'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (emojiQuery != null && emojiRepository != null) ...<Widget>[
                TextFieldTapRegion(
                  groupId: _textFieldTapGroup,
                  child: Align(
                    alignment: AlignmentDirectional.bottomStart,
                    child: SizedBox(
                      key: const ValueKey<String>('composer-emoji-suggestions'),
                      width: constraints.maxWidth < 560
                          ? constraints.maxWidth
                          : 560,
                      height: constraints.maxWidth < AppBreakpoints.compact
                          ? 208
                          : 264,
                      child: Semantics(
                        liveRegion: true,
                        label: MessageComposerStrings.emojiSuggestions(
                          emojiQuery.term,
                        ),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          clipBehavior: Clip.antiAlias,
                          elevation: 6,
                          child: EmojiSearchResults(
                            query: emojiQuery.term,
                            repository: emojiRepository,
                            accountId: widget.accountId,
                            navigationController: _emojiNavigation,
                            limit: 48,
                            onSelected: _selectEmoji,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border.all(
                    color: _failed ? colors.error : colors.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 6, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: CallbackShortcuts(
                          bindings: <ShortcutActivator, VoidCallback>{
                            const SingleActivator(
                              LogicalKeyboardKey.enter,
                            ): () {
                              _submitOrSelectEmoji();
                            },
                            const SingleActivator(
                              LogicalKeyboardKey.enter,
                              shift: true,
                            ): _insertNewLine,
                            const SingleActivator(
                              LogicalKeyboardKey.numpadEnter,
                            ): _submitOrSelectEmoji,
                            const SingleActivator(
                              LogicalKeyboardKey.numpadEnter,
                              shift: true,
                            ): _insertNewLine,
                            if (emojiQuery !=
                                null) ...<ShortcutActivator, VoidCallback>{
                              const SingleActivator(
                                LogicalKeyboardKey.arrowDown,
                              ): () =>
                                  _emojiNavigation.move(1),
                              const SingleActivator(
                                LogicalKeyboardKey.arrowUp,
                              ): () =>
                                  _emojiNavigation.move(-1),
                              const SingleActivator(LogicalKeyboardKey.escape):
                                  _dismissEmojiAutocomplete,
                            },
                            const SingleActivator(
                              LogicalKeyboardKey.keyC,
                              control: true,
                            ): () =>
                                _copySelection(cut: false),
                            const SingleActivator(
                              LogicalKeyboardKey.keyC,
                              meta: true,
                            ): () =>
                                _copySelection(cut: false),
                            const SingleActivator(
                              LogicalKeyboardKey.keyX,
                              control: true,
                            ): () =>
                                _copySelection(cut: true),
                            const SingleActivator(
                              LogicalKeyboardKey.keyX,
                              meta: true,
                            ): () =>
                                _copySelection(cut: true),
                          },
                          child: TextField(
                            key: ValueKey<String>(
                              'message-input-${widget.destinationId}',
                            ),
                            controller: _controller,
                            focusNode: _focusNode,
                            groupId: _textFieldTapGroup,
                            readOnly: _sending,
                            minLines: 1,
                            maxLines: 6,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            spellCheckConfiguration:
                                const SpellCheckConfiguration.disabled(),
                            contextMenuBuilder: _buildContextMenu,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: widget.placeholder,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Semantics(
                        button: true,
                        label: _sending
                            ? MessageComposerStrings.sending
                            : MessageComposerStrings.send,
                        child: IconButton.filled(
                          key: ValueKey<String>(
                            'send-message-${widget.destinationId}',
                          ),
                          tooltip: MessageComposerStrings.send,
                          onPressed: _canSend
                              ? () =>
                                    unawaited(_submit(finalizeComposing: true))
                              : null,
                          icon: _sending
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_failed) ...<Widget>[
                const SizedBox(height: 6),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    MessageComposerStrings.sendFailed,
                    key: ValueKey<String>(
                      'message-send-error-${widget.destinationId}',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
