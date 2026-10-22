import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/models/user_mention.dart';
import 'package:mattermost_flutter/src/domain/repositories/emoji_repository.dart';
import 'package:mattermost_flutter/src/features/file_upload/domain/file_upload.dart';
import 'package:mattermost_flutter/src/features/file_upload/presentation/composer_upload_controller.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/find_mention_query.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/mention_query.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/group_mention.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_candidate.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/repositories/mention_repository.dart';
import 'package:mattermost_flutter/src/features/mentions/presentation/mention_autocomplete_controller.dart';
import 'package:mattermost_flutter/src/features/mentions/presentation/mention_suggestion_panel.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_breakpoints.dart';
import 'package:mattermost_flutter/src/ui/messages/message_composer_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/message_editor_controller.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/emoji_picker.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/file_attachment_presentation.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/full_message_editor.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_formatting_toolbar.dart';
import 'package:mattermost_flutter/src/ui/users/widgets/user_profile_card.dart';

typedef SubmitMessage =
    Future<void> Function(String message, String pendingPostId);
typedef SubmitPost =
    Future<void> Function(
      String message,
      String pendingPostId,
      List<String> fileIds,
    );

/// Presentation command surface for inserting content into a composer.
final class MessageComposerController {
  _MessageComposerState? _state;

  /// Inserts [text] as a Markdown block quote and focuses the composer.
  void insertQuote(String text) => _state?._insertQuote(text);

  /// Starts editing a post while preserving the current unsent draft.
  void editPost({required String postId, required String message}) =>
      _state?._beginEdit(postId, message);

  void _attach(_MessageComposerState state) => _state = state;

  void _detach(_MessageComposerState state) {
    if (identical(_state, state)) _state = null;
  }
}

/// Formats selected display text as a Mattermost Markdown block quote.
String formatMarkdownQuote(String text) => text
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .split('\n')
    .map((String line) => '> $line')
    .join('\n');

/// Shared composer for channel posts and thread replies.
class MessageComposer extends StatefulWidget {
  const MessageComposer({
    required this.destinationId,
    required this.placeholder,
    required this.onSubmit,
    this.emojiRepositoryFactory,
    this.mentionRepositoryFactory,
    this.teamId,
    this.channelId,
    this.accountId = '',
    this.composerController,
    this.onSubmitWithFiles,
    this.onEdit,
    this.uploadFilePickerFactory,
    this.fileUploadRepositoryFactory,
    super.key,
  });

  final String destinationId;
  final String placeholder;
  final SubmitMessage onSubmit;
  final SubmitPost? onSubmitWithFiles;
  final Future<void> Function(String postId, String message)? onEdit;
  final UploadFilePicker Function()? uploadFilePickerFactory;
  final FileUploadRepository Function()? fileUploadRepositoryFactory;
  final CustomEmojiRepository Function()? emojiRepositoryFactory;
  final MentionRepository Function()? mentionRepositoryFactory;
  final String? teamId;
  final String? channelId;
  final String accountId;
  final MessageComposerController? composerController;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  late final MessageEditorController _controller;
  late final FocusNode _focusNode;
  final EmojiSearchNavigationController _emojiNavigation =
      EmojiSearchNavigationController();
  final MentionSuggestionNavigationController _mentionNavigation =
      MentionSuggestionNavigationController();
  final Object _textFieldTapGroup = Object();
  CustomEmojiRepository? _emojiRepository;
  MentionAutocompleteController? _mentionController;
  bool _sending = false;
  bool _picking = false;
  bool _failed = false;
  bool _fullEditorOpen = false;
  bool _pickFailed = false;
  bool _tooManyFiles = false;
  int _scopeGeneration = 0;
  ComposerUploadController? _uploads;
  String? _pendingPostId;
  String? _pendingDraft;
  String? _editingPostId;
  String? _originalMessage;
  TextEditingValue? _savedDraft;
  String? _dismissedEmojiQuery;
  String? _dismissedMentionQuery;

  bool get _canSend =>
      !_sending &&
      (_editingPostId == null || widget.onEdit != null) &&
      !_picking &&
      (_editingPostId != null || (_uploads?.ready ?? true)) &&
      (_editingPostId != null ||
          (_uploads?.tiles.isEmpty ?? true) ||
          widget.onSubmitWithFiles != null) &&
      (_editingPostId != null
          ? _controller.messageText.trim().isNotEmpty &&
                _controller.messageText != _originalMessage
          : _controller.messageText.trim().isNotEmpty ||
                (_uploads?.tiles.isNotEmpty ?? false));

  void _beginEdit(String postId, String message) {
    if (_sending || widget.onEdit == null || postId.isEmpty) return;
    _savedDraft ??= _controller.value;
    setState(() {
      _editingPostId = postId;
      _originalMessage = message;
      _failed = false;
      _controller.value = TextEditingValue(
        text: message,
        selection: TextSelection.collapsed(offset: message.length),
      );
    });
    _focusNode.requestFocus();
  }

  void _finishEdit({bool restoreFocus = true}) {
    final TextEditingValue? draft = _savedDraft;
    setState(() {
      _editingPostId = null;
      _originalMessage = null;
      _savedDraft = null;
      _failed = false;
      _controller.value = draft ?? TextEditingValue.empty;
    });
    if (restoreFocus) {
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
    }
  }

  void _onUploadsChanged() {
    if (mounted) setState(() {});
  }

  void _resetUploads() {
    _uploads?.removeListener(_onUploadsChanged);
    _uploads?.dispose();
    _uploads = null;
  }

  Future<void> _pickFiles() async {
    final UploadFilePicker Function()? picker = widget.uploadFilePickerFactory;
    _initUploads();
    final ComposerUploadController? uploads = _uploads;
    if (picker == null ||
        uploads == null ||
        !uploads.canAdd ||
        _sending ||
        _picking) {
      return;
    }
    setState(() => _picking = true);
    try {
      final files = await picker().pickFiles();
      if (!mounted || uploads != _uploads || files.isEmpty) return;
      if (!uploads.addFiles(files)) {
        setState(() {
          _pickFailed = true;
          _tooManyFiles = true;
        });
      } else {
        _pendingPostId = null;
        _pendingDraft = null;
        setState(() => _pickFailed = false);
      }
    } on Object {
      if (mounted && uploads == _uploads) {
        setState(() {
          _pickFailed = true;
          _tooManyFiles = false;
        });
      }
    } finally {
      if (mounted && uploads == _uploads) {
        setState(() => _picking = false);
        _focusNode.requestFocus();
      }
    }
  }

  void _removeFile(int localId) {
    _uploads?.remove(localId);
    _pendingPostId = null;
    _pendingDraft = null;
  }

  CustomEmojiRepository? get _availableEmojiRepository {
    final CustomEmojiRepository Function()? factory =
        widget.emojiRepositoryFactory;
    if (factory == null || widget.accountId.isEmpty) return null;
    return _emojiRepository ??= factory();
  }

  MentionAutocompleteController? get _availableMentionController {
    final MentionRepository Function()? factory =
        widget.mentionRepositoryFactory;
    final String? teamId = widget.teamId;
    final String? channelId = widget.channelId;
    if (factory == null ||
        teamId == null ||
        channelId == null ||
        teamId.isEmpty ||
        channelId.isEmpty ||
        widget.accountId.isEmpty) {
      return null;
    }
    return _mentionController ??= MentionAutocompleteController(
      repository: factory(),
      teamId: teamId,
      channelId: channelId,
      limit: 25,
    )..addListener(_onMentionChanged);
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

  MentionQuery? get _visibleMentionQuery {
    if (_sending || !_focusNode.hasFocus || _visibleEmojiQuery != null) {
      return null;
    }
    final MentionQuery? query = findMentionQuery(
      text: _controller.text,
      selectionStart: _controller.selection.start,
      selectionEnd: _controller.selection.end,
    );
    if (query == null ||
        _mentionQueryKey(query) == _dismissedMentionQuery ||
        _availableMentionController == null) {
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
      userMentionBuilder: (BuildContext context, UserMention mention) =>
          GestureDetector(
            onTap: () => unawaited(
              showUserProfileCard(
                context,
                userId: mention.userId,
                onMessage: (_) async {},
              ),
            ),
            child: Text(
              '@${mention.displayName}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      groupMentionBuilder: (BuildContext context, GroupMention mention) => Text(
        '@${mention.name}',
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    )..addListener(_onTextChanged);
    widget.composerController?._attach(this);
  }

  void _initUploads() {
    if (_uploads != null) return;
    final FileUploadRepository Function()? factory =
        widget.fileUploadRepositoryFactory;
    final String? channelId = widget.channelId;
    if (factory == null || channelId == null || widget.accountId.isEmpty) {
      return;
    }
    _uploads = ComposerUploadController(
      repository: factory(),
      channelId: channelId,
    )..addListener(_onUploadsChanged);
  }

  @override
  void didUpdateWidget(covariant MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composerController != widget.composerController) {
      oldWidget.composerController?._detach(this);
      widget.composerController?._attach(this);
    }
    if (oldWidget.destinationId != widget.destinationId ||
        oldWidget.channelId != widget.channelId ||
        oldWidget.accountId != widget.accountId) {
      _scopeGeneration++;
      _sending = false;
      _picking = false;
      _resetUploads();
      _controller.clear();
      _pendingPostId = null;
      _pendingDraft = null;
      _editingPostId = null;
      _originalMessage = null;
      _savedDraft = null;
      _failed = false;
      _pickFailed = false;
      _dismissedMentionQuery = null;
      _mentionController?.dispose();
      _mentionController = null;
    }
    if (oldWidget.accountId != widget.accountId) {
      _emojiRepository = null;
      _controller.clear();
      _mentionController?.dispose();
      _mentionController = null;
    }
  }

  @override
  void dispose() {
    _scopeGeneration++;
    _resetUploads();
    widget.composerController?._detach(this);
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    _emojiNavigation.dispose();
    _mentionController?.dispose();
    _mentionNavigation.dispose();
    super.dispose();
  }

  void _insertQuote(String selectedText) {
    if (_sending || selectedText.isEmpty) return;
    final TextEditingValue value = _controller.value;
    final TextSelection selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final bool startsAtLineBoundary =
        selection.start == 0 || value.text[selection.start - 1] == '\n';
    final String quoted = formatMarkdownQuote(selectedText);
    final String replacement = '${startsAtLineBoundary ? '' : '\n'}$quoted\n\n';
    _controller
      ..selection = selection
      ..replaceSelectionWithText(replacement);
    _focusNode.requestFocus();
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
    final MentionQuery? mentionQuery = findMentionQuery(
      text: _controller.text,
      selectionStart: _controller.selection.start,
      selectionEnd: _controller.selection.end,
    );
    if (mentionQuery == null ||
        _mentionQueryKey(mentionQuery) != _dismissedMentionQuery) {
      _dismissedMentionQuery = null;
    }
    if (mentionQuery == null) {
      _mentionController?.updateQuery(null);
    } else {
      _availableMentionController?.updateQuery(mentionQuery);
    }
    if (mounted) setState(() {});
  }

  void _onMentionChanged() {
    final MentionAutocompleteController? controller = _mentionController;
    final result = controller?.state.result;
    if (result != null) {
      _mentionNavigation.setOptions(result.orderedSuggestions);
    }
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _onTextChanged();
    } else {
      _mentionController?.updateQuery(null);
      if (mounted) setState(() {});
    }
  }

  String _emojiQueryKey(EmojiAutocompleteQuery query) =>
      '${query.range.start}:${query.term}';

  String _mentionQueryKey(MentionQuery query) =>
      '${query.start}:${query.end}:${query.key}';

  Future<bool> _submit({bool finalizeComposing = false}) async {
    if (!_canSend) return false;
    final TextEditingValue value = _controller.value;
    if (value.composing.isValid && !value.composing.isCollapsed) {
      if (!finalizeComposing) return false;
      // Android keyboards such as Gboard keep the word at the caret in a
      // composing region for autocorrect. An explicit send action finalizes
      // that word; it must not silently discard the tap while the IME is open.
      _controller.clearComposing();
    }

    final String message = _controller.messageText;
    final String? editingPostId = _editingPostId;
    if (editingPostId != null) {
      setState(() {
        _sending = true;
        _failed = false;
      });
      try {
        await widget.onEdit!(editingPostId, message);
        if (!mounted || _editingPostId != editingPostId) return false;
        _finishEdit(restoreFocus: false);
        return true;
      } on Object {
        if (mounted && _editingPostId == editingPostId) {
          setState(() => _failed = true);
        }
        return false;
      } finally {
        if (mounted) setState(() => _sending = false);
      }
    }
    final String draft = _controller.messageText;
    final List<String> fileIds = _uploads?.uploadedIds ?? const <String>[];
    final ComposerUploadController? uploads = _uploads;
    final String destinationId = widget.destinationId;
    final String accountId = widget.accountId;
    final int scopeGeneration = _scopeGeneration;
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
      if (widget.onSubmitWithFiles case final SubmitPost submit) {
        await submit(message, pendingPostId, fileIds);
      } else {
        await widget.onSubmit(message, pendingPostId);
      }
      if (!mounted ||
          destinationId != widget.destinationId ||
          accountId != widget.accountId ||
          uploads != _uploads ||
          scopeGeneration != _scopeGeneration) {
        return false;
      }
      if (_controller.messageText == draft) _controller.clear();
      uploads?.clear();
      _pendingPostId = null;
      _pendingDraft = null;
      _focusNode.unfocus();
      return true;
    } on Object {
      if (!mounted ||
          destinationId != widget.destinationId ||
          accountId != widget.accountId ||
          uploads != _uploads ||
          scopeGeneration != _scopeGeneration) {
        return false;
      }
      setState(() => _failed = true);
      if (!_fullEditorOpen) _focusNode.requestFocus();
      return false;
    } finally {
      if (mounted && scopeGeneration == _scopeGeneration) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _openFullEditor() async {
    if (_sending) return;
    if (_editingPostId == null) _initUploads();
    _focusNode.unfocus();
    final bool compact =
        MediaQuery.sizeOf(context).width < AppBreakpoints.compact;
    _fullEditorOpen = true;
    bool? submitted;
    try {
      submitted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          final Size size = MediaQuery.sizeOf(dialogContext);
          final Widget editor = FullMessageEditor(
            destinationId: widget.destinationId,
            placeholder: widget.placeholder,
            controller: _controller,
            uploads: _editingPostId == null ? _uploads : null,
            editing: _editingPostId != null,
            canSend: () => _canSend,
            canAttach: () =>
                (_uploads?.canAdd ?? true) && !_sending && !_picking,
            onAttach:
                _editingPostId == null &&
                    widget.fileUploadRepositoryFactory != null &&
                    widget.uploadFilePickerFactory != null &&
                    widget.accountId.isNotEmpty
                ? _pickFiles
                : null,
            onSubmit: () => _submit(finalizeComposing: true),
            onInsertNewLine: _insertNewLine,
            uploadTilesBuilder: () => _editingPostId == null
                ? _uploads?.tiles
                          .map(_buildUploadTile)
                          .toList(growable: false) ??
                      const <Widget>[]
                : const <Widget>[],
            contextMenuBuilder: _buildContextMenu,
            accountId: widget.accountId,
            emojiRepository: _availableEmojiRepository,
            mentionController: _availableMentionController,
            onEmojiSelected: _selectEmoji,
            onMentionSelected: _selectMentionForQuery,
          );
          if (compact) {
            return Dialog.fullscreen(
              key: const ValueKey<String>('full-editor-fullscreen'),
              child: editor,
            );
          }
          return Dialog(
            key: const ValueKey<String>('full-editor-modal'),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 840,
              height: (size.height * 0.72).clamp(480, 720),
              child: editor,
            ),
          );
        },
      );
    } finally {
      _fullEditorOpen = false;
    }
    if (mounted && !_sending && submitted != true) _focusNode.requestFocus();
  }

  void _insertNewLine() {
    if (_sending) return;
    final TextEditingValue value = _controller.value;
    final TextSelection selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    if (!selection.isCollapsed) {
      _replaceSelectionWithNewLine(value, selection, '\n');
      return;
    }
    final int lineStart = value.text.lastIndexOf('\n', selection.start - 1) + 1;
    final int lineEnd = value.text.indexOf('\n', selection.start);
    final int boundedLineEnd = lineEnd < 0 ? value.text.length : lineEnd;
    final String beforeCaret = value.text.substring(lineStart, selection.start);
    final String afterCaret = value.text.substring(
      selection.start,
      boundedLineEnd,
    );

    // A code fence intentionally keeps native multiline input behaviour.
    if (_isInsideFencedCodeBlock(value.text, lineStart)) {
      _replaceSelectionWithNewLine(value, selection, '\n');
      return;
    }
    final RegExpMatch? unordered = RegExp(
      r'^( {0,3}[-+*] )(.*)$',
    ).firstMatch(beforeCaret);
    final RegExpMatch? ordered = RegExp(
      r'^( {0,3})([0-9]+)\. (.*)$',
    ).firstMatch(beforeCaret);
    final RegExpMatch? quote = RegExp(
      r'^( {0,3}> )(.*)$',
    ).firstMatch(beforeCaret);
    if (afterCaret.isEmpty &&
        ((unordered != null && unordered.group(2)!.isEmpty) ||
            (ordered != null && ordered.group(3)!.isEmpty) ||
            (quote != null && quote.group(2)!.isEmpty))) {
      // A second explicit newline on an empty list item/quote exits the block.
      _controller.value = value.copyWith(
        text: value.text.replaceRange(lineStart, selection.start, ''),
        selection: TextSelection.collapsed(offset: lineStart),
        composing: TextRange.empty,
      );
      return;
    }
    if (unordered != null) {
      _replaceSelectionWithNewLine(
        value,
        selection,
        '\n${unordered.group(1)!}',
      );
      return;
    }
    if (ordered != null) {
      final int nextNumber = int.parse(ordered.group(2)!) + 1;
      _replaceSelectionWithNewLine(
        value,
        selection,
        '\n${ordered.group(1)!}$nextNumber. ',
      );
      return;
    }
    if (quote != null) {
      _replaceSelectionWithNewLine(value, selection, '\n${quote.group(1)!}');
      return;
    }
    _replaceSelectionWithNewLine(value, selection, '\n');
  }

  void _replaceSelectionWithNewLine(
    TextEditingValue value,
    TextSelection selection,
    String replacement,
  ) {
    final String text = value.text.replaceRange(
      selection.start,
      selection.end,
      replacement,
    );
    _controller.value = value.copyWith(
      text: text,
      selection: TextSelection.collapsed(
        offset: selection.start + replacement.length,
      ),
      composing: TextRange.empty,
    );
  }

  bool _isInsideFencedCodeBlock(String text, int lineStart) {
    final Iterable<String> precedingLines = text
        .substring(0, lineStart)
        .split('\n');
    var fences = 0;
    for (final String line in precedingLines) {
      if (RegExp(r'^ {0,3}```').hasMatch(line)) fences += 1;
    }
    return fences.isOdd;
  }

  void _submitOrSelectEmoji() {
    final MentionSuggestion? mention = _visibleMentionQuery == null
        ? null
        : _mentionNavigation.highlightedCandidate;
    if (mention != null) {
      _selectMention(mention);
      return;
    }
    final EmojiSuggestion? suggestion = _visibleEmojiQuery == null
        ? null
        : _emojiNavigation.highlightedSuggestion;
    if (suggestion != null) {
      _selectEmoji(suggestion);
      return;
    }
    unawaited(_submit());
  }

  void _selectMention(MentionSuggestion candidate) {
    final MentionQuery? query = _visibleMentionQuery;
    if (query == null) return;
    _selectMentionForQuery(query, candidate);
    _focusNode.requestFocus();
  }

  void _selectMentionForQuery(MentionQuery query, MentionSuggestion candidate) {
    switch (candidate) {
      case MentionCandidate(:final user):
        _controller.replaceQueryWithMention(
          query,
          userMentionFromSummary(user),
        );
      case GroupMentionCandidate(:final group):
        _controller.replaceQueryWithGroupMention(query, group);
    }
    _dismissedMentionQuery = null;
    _mentionController?.dismiss();
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
    if (!_fullEditorOpen) _focusNode.requestFocus();
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

  void _dismissMentionAutocomplete() {
    final MentionQuery? query = _visibleMentionQuery;
    if (query == null) return;
    setState(() => _dismissedMentionQuery = _mentionQueryKey(query));
    _mentionController?.dismiss();
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

  Widget _buildMessageInput({
    required MentionQuery? mentionQuery,
    required EmojiAutocompleteQuery? emojiQuery,
    required bool autocompleteOwnsShortcuts,
    required bool imeOwnsShortcuts,
  }) => CallbackShortcuts(
    bindings: <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.enter): () {
        _submitOrSelectEmoji();
      },
      const SingleActivator(LogicalKeyboardKey.enter, shift: true):
          _insertNewLine,
      const SingleActivator(LogicalKeyboardKey.numpadEnter):
          _submitOrSelectEmoji,
      const SingleActivator(LogicalKeyboardKey.numpadEnter, shift: true):
          _insertNewLine,
      if (mentionQuery != null) ...<ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _mentionNavigation.move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _mentionNavigation.move(-1),
        const SingleActivator(LogicalKeyboardKey.escape):
            _dismissMentionAutocomplete,
        const SingleActivator(LogicalKeyboardKey.tab): _submitOrSelectEmoji,
      } else if (emojiQuery != null) ...<ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _emojiNavigation.move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _emojiNavigation.move(-1),
        const SingleActivator(LogicalKeyboardKey.escape):
            _dismissEmojiAutocomplete,
      },
      const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
          _copySelection(cut: false),
      const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () =>
          _copySelection(cut: false),
      const SingleActivator(LogicalKeyboardKey.keyX, control: true): () =>
          _copySelection(cut: true),
      const SingleActivator(LogicalKeyboardKey.keyX, meta: true): () =>
          _copySelection(cut: true),
      if (!autocompleteOwnsShortcuts &&
          !imeOwnsShortcuts) ...<ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
            _controller.applyFormattingCommand(MessageFormattingCommand.bold),
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
            _controller.applyFormattingCommand(MessageFormattingCommand.bold),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
            _controller.applyFormattingCommand(MessageFormattingCommand.italic),
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () =>
            _controller.applyFormattingCommand(MessageFormattingCommand.italic),
      },
    },
    child: TextField(
      key: ValueKey<String>('message-input-${widget.destinationId}'),
      controller: _controller,
      focusNode: _focusNode,
      groupId: _textFieldTapGroup,
      readOnly: _sending,
      minLines: 1,
      maxLines: 6,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
      contextMenuBuilder: _buildContextMenu,
      decoration: InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        hintText: widget.placeholder,
      ),
    ),
  );

  Widget _buildFullEditorButton() => IconButton(
    key: ValueKey<String>('open-full-editor-${widget.destinationId}'),
    tooltip: MessageComposerStrings.openFullEditor,
    onPressed: _sending ? null : () => unawaited(_openFullEditor()),
    icon: const Icon(Icons.edit_note_outlined),
  );

  Widget _buildSendButton() => Semantics(
    button: true,
    label: _editingPostId != null
        ? MessageComposerStrings.saveEdit
        : _sending
        ? MessageComposerStrings.sending
        : MessageComposerStrings.send,
    child: IconButton.filled(
      key: ValueKey<String>('send-message-${widget.destinationId}'),
      tooltip: _editingPostId != null
          ? MessageComposerStrings.saveEdit
          : MessageComposerStrings.send,
      onPressed: _canSend
          ? () => unawaited(_submit(finalizeComposing: true))
          : null,
      icon: _sending
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.send_rounded),
    ),
  );

  Widget? _buildAttachmentButton() {
    if (_editingPostId != null ||
        widget.fileUploadRepositoryFactory == null ||
        widget.uploadFilePickerFactory == null ||
        widget.accountId.isEmpty) {
      return null;
    }
    return IconButton(
      key: ValueKey<String>('attach-file-${widget.destinationId}'),
      tooltip: MessageComposerStrings.attach,
      onPressed: (_uploads?.canAdd ?? true) && !_sending && !_picking
          ? () => unawaited(_pickFiles())
          : null,
      icon: const Icon(Icons.attach_file),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final EmojiAutocompleteQuery? emojiQuery = _visibleEmojiQuery;
    final MentionQuery? mentionQuery = _visibleMentionQuery;
    final MentionAutocompleteController? mentionController =
        mentionQuery == null ? null : _availableMentionController;
    final CustomEmojiRepository? emojiRepository = emojiQuery == null
        ? null
        : _availableEmojiRepository;
    final bool autocompleteOwnsShortcuts =
        mentionQuery != null || emojiQuery != null;
    final bool imeOwnsShortcuts =
        _controller.value.composing.isValid &&
        !_controller.value.composing.isCollapsed;
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
              if (mentionQuery != null && mentionController != null)
                TextFieldTapRegion(
                  groupId: _textFieldTapGroup,
                  child: Align(
                    alignment: AlignmentDirectional.bottomStart,
                    child: SizedBox(
                      width: constraints.maxWidth < 560
                          ? constraints.maxWidth
                          : 560,
                      height: constraints.maxWidth < AppBreakpoints.compact
                          ? 208
                          : 264,
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        clipBehavior: Clip.antiAlias,
                        elevation: 6,
                        child: MentionSuggestionPanel(
                          state: mentionController.state,
                          highlightedIndex: _mentionNavigation.highlightedIndex,
                          onSelected: _selectMention,
                          onHighlighted: _mentionNavigation.highlight,
                          onRetry: mentionController.retry,
                          onDismissed: _dismissMentionAutocomplete,
                        ),
                      ),
                    ),
                  ),
                ),
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
              if (_editingPostId != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      const Text(MessageComposerStrings.editing),
                      TextButton(
                        key: const ValueKey<String>('cancel-message-edit'),
                        onPressed: _sending ? null : _finishEdit,
                        child: const Text(MessageComposerStrings.cancelEdit),
                      ),
                    ],
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: _failed
                      ? Border.all(color: colors.error)
                      : isDark
                      ? null
                      : Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 6, 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (_editingPostId == null &&
                          (_uploads?.tiles.isNotEmpty ?? false))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _uploads!.tiles
                                .map(_buildUploadTile)
                                .toList(),
                          ),
                        ),
                      if (constraints.maxWidth <
                          AppBreakpoints.compact) ...<Widget>[
                        _buildMessageInput(
                          mentionQuery: mentionQuery,
                          emojiQuery: emojiQuery,
                          autocompleteOwnsShortcuts: autocompleteOwnsShortcuts,
                          imeOwnsShortcuts: imeOwnsShortcuts,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            if (_buildAttachmentButton()
                                case final Widget attachmentButton) ...<Widget>[
                              attachmentButton,
                              const SizedBox(width: 4),
                            ],
                            _buildFullEditorButton(),
                            const Spacer(),
                            _buildSendButton(),
                          ],
                        ),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            if (_buildAttachmentButton()
                                case final Widget attachmentButton) ...<Widget>[
                              attachmentButton,
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: _buildMessageInput(
                                mentionQuery: mentionQuery,
                                emojiQuery: emojiQuery,
                                autocompleteOwnsShortcuts:
                                    autocompleteOwnsShortcuts,
                                imeOwnsShortcuts: imeOwnsShortcuts,
                              ),
                            ),
                            const SizedBox(width: 4),
                            _buildFullEditorButton(),
                            const SizedBox(width: 4),
                            _buildSendButton(),
                          ],
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
                    _editingPostId != null
                        ? MessageComposerStrings.editFailed
                        : MessageComposerStrings.sendFailed,
                    key: ValueKey<String>(
                      'message-send-error-${widget.destinationId}',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.error,
                    ),
                  ),
                ),
              ],
              if (_pickFailed)
                Text(
                  _tooManyFiles
                      ? MessageComposerStrings.tooManyFiles
                      : MessageComposerStrings.pickerFailed,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.error,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadTile(UploadTile tile) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String status = switch (tile.status) {
      UploadTileStatus.queued => MessageComposerStrings.uploadQueued,
      UploadTileStatus.uploading => '${tile.percent}%',
      UploadTileStatus.finalizing => MessageComposerStrings.uploadFinalizing,
      UploadTileStatus.uploaded => MessageComposerStrings.uploadReady,
      UploadTileStatus.failed => switch (tile.failure) {
        UploadFailure.tooLarge => MessageComposerStrings.fileTooLarge,
        UploadFailure.forbidden => MessageComposerStrings.uploadForbidden,
        UploadFailure.unauthorized => MessageComposerStrings.signInAgain,
        UploadFailure.rateLimited => MessageComposerStrings.retryLater,
        UploadFailure.invalidFile => MessageComposerStrings.invalidFile,
        _ => MessageComposerStrings.uploadFailed,
      },
    };
    return Semantics(
      label: '${tile.name}, $status',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(attachmentFileIcon(tile.type), size: 20),
                const SizedBox(width: 6),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        tile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        status,
                        style: TextStyle(
                          color: tile.status == UploadTileStatus.failed
                              ? colors.error
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        MessageComposerStrings.fileDetails(
                          tile.type,
                          tile.size,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (tile.status == UploadTileStatus.uploading)
                        LinearProgressIndicator(value: tile.percent / 100),
                    ],
                  ),
                ),
                if (tile.status == UploadTileStatus.failed)
                  IconButton(
                    tooltip: MessageComposerStrings.retryUpload,
                    onPressed: tile.retryAt == null
                        ? () => _uploads?.retry(tile.localId)
                        : null,
                    icon: const Icon(Icons.refresh),
                  ),
                IconButton(
                  tooltip: MessageComposerStrings.removeFile,
                  onPressed: _sending ? null : () => _removeFile(tile.localId),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
