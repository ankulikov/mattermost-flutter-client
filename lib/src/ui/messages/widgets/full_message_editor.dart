import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mattermost_flutter/src/domain/repositories/emoji_repository.dart';
import 'package:mattermost_flutter/src/features/file_upload/presentation/composer_upload_controller.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/find_mention_query.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/mention_query.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_candidate.dart';
import 'package:mattermost_flutter/src/features/mentions/presentation/mention_autocomplete_controller.dart';
import 'package:mattermost_flutter/src/features/mentions/presentation/mention_suggestion_panel.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_breakpoints.dart';
import 'package:mattermost_flutter/src/ui/messages/message_composer_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/message_editor_controller.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/emoji_picker.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_formatting_toolbar.dart';

typedef ComposerContextMenuBuilder =
    Widget Function(BuildContext, EditableTextState);
typedef MentionSuggestionSelected =
    void Function(MentionQuery query, MentionSuggestion suggestion);

/// Builds the full message editing surface used by modal and full-screen routes.
class FullMessageEditor extends StatefulWidget {
  const FullMessageEditor({
    required this.destinationId,
    required this.placeholder,
    required this.controller,
    required this.uploads,
    required this.canSend,
    required this.canAttach,
    required this.onAttach,
    required this.onSubmit,
    required this.onInsertNewLine,
    required this.uploadTilesBuilder,
    required this.contextMenuBuilder,
    required this.accountId,
    required this.onEmojiSelected,
    required this.onMentionSelected,
    this.emojiRepository,
    this.mentionController,
    this.editing = false,
    super.key,
  });

  final String destinationId;
  final String placeholder;
  final MessageEditorController controller;
  final ComposerUploadController? uploads;
  final bool Function() canSend;
  final bool Function() canAttach;
  final Future<void> Function()? onAttach;
  final Future<bool> Function() onSubmit;
  final VoidCallback onInsertNewLine;
  final List<Widget> Function() uploadTilesBuilder;
  final ComposerContextMenuBuilder contextMenuBuilder;
  final String accountId;
  final CustomEmojiRepository? emojiRepository;
  final MentionAutocompleteController? mentionController;
  final ValueChanged<EmojiSuggestion> onEmojiSelected;
  final MentionSuggestionSelected onMentionSelected;
  final bool editing;

  @override
  State<FullMessageEditor> createState() => _FullMessageEditorState();
}

class _FullMessageEditorState extends State<FullMessageEditor> {
  late final FocusNode _focusNode;
  late final Listenable _changes;
  final EmojiSearchNavigationController _emojiNavigation =
      EmojiSearchNavigationController();
  final MentionSuggestionNavigationController _mentionNavigation =
      MentionSuggestionNavigationController();
  final Object _textFieldTapGroup = Object();
  bool _submitting = false;
  bool _picking = false;
  bool _failed = false;
  String? _dismissedEmojiQuery;
  String? _dismissedMentionQuery;

  EmojiAutocompleteQuery? get _visibleEmojiQuery {
    if (_submitting || !_focusNode.hasFocus || widget.emojiRepository == null) {
      return null;
    }
    final EmojiAutocompleteQuery? query =
        widget.controller.emojiAutocompleteQuery;
    if (query == null || _emojiQueryKey(query) == _dismissedEmojiQuery) {
      return null;
    }
    return query;
  }

  MentionQuery? get _visibleMentionQuery {
    if (_submitting ||
        !_focusNode.hasFocus ||
        _visibleEmojiQuery != null ||
        widget.mentionController == null) {
      return null;
    }
    final MentionQuery? query = findMentionQuery(
      text: widget.controller.text,
      selectionStart: widget.controller.selection.start,
      selectionEnd: widget.controller.selection.end,
    );
    if (query == null || _mentionQueryKey(query) == _dismissedMentionQuery) {
      return null;
    }
    return query;
  }

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_onFocusChanged);
    _changes = Listenable.merge(<Listenable>[
      widget.controller,
      if (widget.uploads case final ComposerUploadController uploads) uploads,
    ]);
    widget.controller.addListener(_onEditorChanged);
    widget.mentionController?.addListener(_onMentionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant FullMessageEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onEditorChanged);
      widget.controller.addListener(_onEditorChanged);
    }
    if (oldWidget.mentionController != widget.mentionController) {
      oldWidget.mentionController?.removeListener(_onMentionChanged);
      widget.mentionController?.addListener(_onMentionChanged);
      _onMentionChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onEditorChanged);
    widget.mentionController?.removeListener(_onMentionChanged);
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    _emojiNavigation.dispose();
    _mentionNavigation.dispose();
    super.dispose();
  }

  void _onEditorChanged() {
    final EmojiAutocompleteQuery? emojiQuery =
        widget.controller.emojiAutocompleteQuery;
    if (emojiQuery == null ||
        _emojiQueryKey(emojiQuery) != _dismissedEmojiQuery) {
      _dismissedEmojiQuery = null;
    }
    final MentionQuery? mentionQuery = findMentionQuery(
      text: widget.controller.text,
      selectionStart: widget.controller.selection.start,
      selectionEnd: widget.controller.selection.end,
    );
    if (mentionQuery == null ||
        _mentionQueryKey(mentionQuery) != _dismissedMentionQuery) {
      _dismissedMentionQuery = null;
    }
    widget.mentionController?.updateQuery(mentionQuery);
    if (mounted) setState(() {});
  }

  void _onMentionChanged() {
    final result = widget.mentionController?.state.result;
    if (result != null) {
      _mentionNavigation.setOptions(result.orderedSuggestions);
    }
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _onEditorChanged();
    } else {
      widget.mentionController?.updateQuery(null);
      if (mounted) setState(() {});
    }
  }

  String _emojiQueryKey(EmojiAutocompleteQuery query) =>
      '${query.range.start}:${query.term}';

  String _mentionQueryKey(MentionQuery query) =>
      '${query.start}:${query.end}:${query.key}';

  void _submitOrSelectSuggestion() {
    final MentionQuery? mentionQuery = _visibleMentionQuery;
    final MentionSuggestion? mention = mentionQuery == null
        ? null
        : _mentionNavigation.highlightedCandidate;
    if (mentionQuery != null && mention != null) {
      _selectMention(mentionQuery, mention);
      return;
    }
    final EmojiSuggestion? emoji = _visibleEmojiQuery == null
        ? null
        : _emojiNavigation.highlightedSuggestion;
    if (emoji != null) {
      _selectEmoji(emoji);
      return;
    }
    unawaited(_submit());
  }

  void _selectMention(MentionQuery query, MentionSuggestion suggestion) {
    widget.onMentionSelected(query, suggestion);
    _dismissedMentionQuery = null;
    widget.mentionController?.dismiss();
    _focusNode.requestFocus();
  }

  void _selectEmoji(EmojiSuggestion suggestion) {
    widget.onEmojiSelected(suggestion);
    _dismissedEmojiQuery = null;
    _focusNode.requestFocus();
  }

  void _dismissMentionAutocomplete() {
    final MentionQuery? query = _visibleMentionQuery;
    if (query == null) return;
    setState(() => _dismissedMentionQuery = _mentionQueryKey(query));
    widget.mentionController?.dismiss();
  }

  void _dismissEmojiAutocomplete() {
    final EmojiAutocompleteQuery? query = _visibleEmojiQuery;
    if (query == null) return;
    setState(() => _dismissedEmojiQuery = _emojiQueryKey(query));
  }

  Future<void> _submit() async {
    if (_submitting || !widget.canSend()) return;
    setState(() {
      _submitting = true;
      _failed = false;
    });
    final bool sent = await widget.onSubmit();
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _failed = !sent;
    });
    if (sent) {
      Navigator.of(context).pop(true);
    } else {
      _focusNode.requestFocus();
    }
  }

  Future<void> _attach() async {
    final Future<void> Function()? attach = widget.onAttach;
    if (attach == null || _picking || !widget.canAttach()) return;
    setState(() => _picking = true);
    await attach();
    if (mounted) {
      setState(() => _picking = false);
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final EmojiAutocompleteQuery? emojiQuery = _visibleEmojiQuery;
    final MentionQuery? mentionQuery = _visibleMentionQuery;
    final bool autocompleteOwnsShortcuts =
        mentionQuery != null || emojiQuery != null;
    final bool imeOwnsShortcuts =
        widget.controller.value.composing.isValid &&
        !widget.controller.value.composing.isCollapsed;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
            child: Row(
              children: <Widget>[
                IconButton(
                  key: const ValueKey<String>('close-full-editor'),
                  tooltip: MessageComposerStrings.closeFullEditor,
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.editing
                        ? MessageComposerStrings.editing
                        : MessageComposerStrings.fullEditorTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                AnimatedBuilder(
                  animation: _changes,
                  builder: (BuildContext context, Widget? child) =>
                      IconButton.filled(
                        key: ValueKey<String>(
                          'full-editor-send-${widget.destinationId}',
                        ),
                        tooltip: widget.editing
                            ? MessageComposerStrings.saveEdit
                            : MessageComposerStrings.send,
                        onPressed: !_submitting && widget.canSend()
                            ? _submit
                            : null,
                        icon: _submitting
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
          const Divider(height: 1),
          AnimatedBuilder(
            animation: _changes,
            builder: (BuildContext context, Widget? child) {
              final List<Widget> tiles = widget.uploadTilesBuilder();
              if (tiles.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(spacing: 8, runSpacing: 8, children: tiles),
              );
            },
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
            child: AnimatedBuilder(
              animation: _changes,
              builder: (BuildContext context, Widget? child) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (widget.onAttach != null)
                    IconButton(
                      key: ValueKey<String>(
                        'full-editor-attach-${widget.destinationId}',
                      ),
                      tooltip: MessageComposerStrings.attach,
                      onPressed: !_submitting && !_picking && widget.canAttach()
                          ? _attach
                          : null,
                      icon: const Icon(Icons.attach_file),
                    ),
                  Expanded(
                    child: MessageFormattingToolbar(
                      activeCommands:
                          widget.controller.activeFormattingCommands,
                      editorFocusNode: _focusNode,
                      enabled: !_submitting,
                      showAllCommands: true,
                      onCommandSelected:
                          widget.controller.applyFormattingCommand,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          if (_failed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  widget.editing
                      ? MessageComposerStrings.editFailed
                      : MessageComposerStrings.sendFailed,
                  key: ValueKey<String>(
                    'full-editor-send-error-${widget.destinationId}',
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.error),
                ),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Widget? suggestions = _buildSuggestions(
                  context,
                  constraints,
                  emojiQuery: emojiQuery,
                  mentionQuery: mentionQuery,
                );
                return Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: CallbackShortcuts(
                          bindings: <ShortcutActivator, VoidCallback>{
                            const SingleActivator(LogicalKeyboardKey.enter):
                                _submitOrSelectSuggestion,
                            const SingleActivator(
                              LogicalKeyboardKey.enter,
                              shift: true,
                            ): widget.onInsertNewLine,
                            const SingleActivator(
                              LogicalKeyboardKey.numpadEnter,
                            ): _submitOrSelectSuggestion,
                            const SingleActivator(
                              LogicalKeyboardKey.numpadEnter,
                              shift: true,
                            ): widget.onInsertNewLine,
                            if (mentionQuery !=
                                null) ...<ShortcutActivator, VoidCallback>{
                              const SingleActivator(
                                LogicalKeyboardKey.arrowDown,
                              ): () =>
                                  _mentionNavigation.move(1),
                              const SingleActivator(
                                LogicalKeyboardKey.arrowUp,
                              ): () =>
                                  _mentionNavigation.move(-1),
                              const SingleActivator(LogicalKeyboardKey.escape):
                                  _dismissMentionAutocomplete,
                              const SingleActivator(LogicalKeyboardKey.tab):
                                  _submitOrSelectSuggestion,
                            } else if (emojiQuery !=
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
                            if (!autocompleteOwnsShortcuts &&
                                !imeOwnsShortcuts) ...<
                              ShortcutActivator,
                              VoidCallback
                            >{
                              const SingleActivator(
                                LogicalKeyboardKey.keyB,
                                control: true,
                              ): () => widget.controller.applyFormattingCommand(
                                MessageFormattingCommand.bold,
                              ),
                              const SingleActivator(
                                LogicalKeyboardKey.keyB,
                                meta: true,
                              ): () => widget.controller.applyFormattingCommand(
                                MessageFormattingCommand.bold,
                              ),
                              const SingleActivator(
                                LogicalKeyboardKey.keyI,
                                control: true,
                              ): () => widget.controller.applyFormattingCommand(
                                MessageFormattingCommand.italic,
                              ),
                              const SingleActivator(
                                LogicalKeyboardKey.keyI,
                                meta: true,
                              ): () => widget.controller.applyFormattingCommand(
                                MessageFormattingCommand.italic,
                              ),
                              const SingleActivator(
                                LogicalKeyboardKey.keyK,
                                control: true,
                                alt: true,
                              ): () => widget.controller.applyFormattingCommand(
                                MessageFormattingCommand.link,
                              ),
                              const SingleActivator(
                                LogicalKeyboardKey.keyK,
                                meta: true,
                                alt: true,
                              ): () => widget.controller.applyFormattingCommand(
                                MessageFormattingCommand.link,
                              ),
                            },
                          },
                          child: TextField(
                            key: ValueKey<String>(
                              'full-message-input-${widget.destinationId}',
                            ),
                            controller: widget.controller,
                            focusNode: _focusNode,
                            groupId: _textFieldTapGroup,
                            readOnly: _submitting,
                            expands: true,
                            minLines: null,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            textAlignVertical: TextAlignVertical.top,
                            spellCheckConfiguration:
                                const SpellCheckConfiguration.disabled(),
                            contextMenuBuilder: widget.contextMenuBuilder,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: widget.placeholder,
                            ),
                          ),
                        ),
                      ),
                    ),
                    ?suggestions,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildSuggestions(
    BuildContext context,
    BoxConstraints constraints, {
    required EmojiAutocompleteQuery? emojiQuery,
    required MentionQuery? mentionQuery,
  }) {
    final CustomEmojiRepository? emojiRepository = widget.emojiRepository;
    final MentionAutocompleteController? mentionController =
        widget.mentionController;
    if ((emojiQuery == null || emojiRepository == null) &&
        (mentionQuery == null || mentionController == null)) {
      return null;
    }
    final bool compact = constraints.maxWidth < AppBreakpoints.compact;
    final double targetHeight = compact ? 208 : 264;
    final double height = math.min(
      targetHeight,
      constraints.maxHeight * (compact ? 0.55 : 0.5),
    );
    final double width = math.min(560, constraints.maxWidth - 32);
    return PositionedDirectional(
      start: 16,
      bottom: 16,
      width: width,
      height: height,
      child: TextFieldTapRegion(
        groupId: _textFieldTapGroup,
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          elevation: 8,
          child: mentionQuery != null && mentionController != null
              ? KeyedSubtree(
                  key: const ValueKey<String>(
                    'full-editor-mention-suggestions',
                  ),
                  child: MentionSuggestionPanel(
                    state: mentionController.state,
                    highlightedIndex: _mentionNavigation.highlightedIndex,
                    onSelected: (MentionSuggestion suggestion) =>
                        _selectMention(mentionQuery, suggestion),
                    onHighlighted: _mentionNavigation.highlight,
                    onRetry: mentionController.retry,
                    onDismissed: _dismissMentionAutocomplete,
                  ),
                )
              : Semantics(
                  key: const ValueKey<String>('full-editor-emoji-suggestions'),
                  liveRegion: true,
                  label: MessageComposerStrings.emojiSuggestions(
                    emojiQuery!.term,
                  ),
                  child: EmojiSearchResults(
                    query: emojiQuery.term,
                    repository: emojiRepository!,
                    accountId: widget.accountId,
                    navigationController: _emojiNavigation,
                    limit: 48,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.manual,
                    onSelected: _selectEmoji,
                  ),
                ),
        ),
      ),
    );
  }
}
