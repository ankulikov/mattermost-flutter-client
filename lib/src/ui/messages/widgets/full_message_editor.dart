import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mattermost_flutter/src/features/file_upload/presentation/composer_upload_controller.dart';
import 'package:mattermost_flutter/src/ui/messages/message_composer_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/message_editor_controller.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_formatting_toolbar.dart';

typedef ComposerContextMenuBuilder =
    Widget Function(BuildContext, EditableTextState);

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

  @override
  State<FullMessageEditor> createState() => _FullMessageEditorState();
}

class _FullMessageEditorState extends State<FullMessageEditor> {
  late final FocusNode _focusNode;
  late final Listenable _changes;
  bool _submitting = false;
  bool _picking = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _changes = Listenable.merge(<Listenable>[
      widget.controller,
      if (widget.uploads case final ComposerUploadController uploads) uploads,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
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
      Navigator.of(context).pop();
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
                    MessageComposerStrings.fullEditorTitle,
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
                        tooltip: MessageComposerStrings.send,
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
                  MessageComposerStrings.sendFailed,
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
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.enter): () =>
                      unawaited(_submit()),
                  const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                      widget.onInsertNewLine,
                  const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
                      unawaited(_submit()),
                  const SingleActivator(
                    LogicalKeyboardKey.numpadEnter,
                    shift: true,
                  ): widget.onInsertNewLine,
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
                },
                child: TextField(
                  key: ValueKey<String>(
                    'full-message-input-${widget.destinationId}',
                  ),
                  controller: widget.controller,
                  focusNode: _focusNode,
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
        ],
      ),
    );
  }
}
