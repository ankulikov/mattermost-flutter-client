import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mattermost_flutter/src/features/messages/presentation/message_composer_strings.dart';

typedef SubmitMessage =
    Future<void> Function(String message, String pendingPostId);

/// Shared text-only composer for channel posts and thread replies.
class MessageComposer extends StatefulWidget {
  const MessageComposer({
    required this.destinationId,
    required this.placeholder,
    required this.onSubmit,
    super.key,
  });

  final String destinationId;
  final String placeholder;
  final SubmitMessage onSubmit;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  late final TextEditingController _controller = TextEditingController()
    ..addListener(_onTextChanged);
  late final FocusNode _focusNode = FocusNode();
  bool _sending = false;
  bool _failed = false;
  String? _pendingPostId;
  String? _pendingMessage;

  bool get _canSend => !_sending && _controller.text.trim().isNotEmpty;

  @override
  void didUpdateWidget(covariant MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destinationId != widget.destinationId) {
      _controller.clear();
      _pendingPostId = null;
      _pendingMessage = null;
      _failed = false;
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_pendingMessage != null && _controller.text != _pendingMessage) {
      _pendingPostId = null;
      _pendingMessage = null;
      _failed = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    if (!_canSend) return;
    final TextEditingValue value = _controller.value;
    if (value.composing.isValid && !value.composing.isCollapsed) return;

    final String message = _controller.text;
    final String pendingPostId =
        _pendingPostId ??
        'flutter:${DateTime.now().microsecondsSinceEpoch}:${widget.destinationId}';
    _pendingPostId = pendingPostId;
    _pendingMessage = message;
    setState(() {
      _sending = true;
      _failed = false;
    });
    try {
      await widget.onSubmit(message, pendingPostId);
      if (!mounted) return;
      if (_controller.text == message) _controller.clear();
      _pendingPostId = null;
      _pendingMessage = null;
    } on Object {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _focusNode.requestFocus();
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Semantics(
      container: true,
      label: widget.placeholder,
      child: Padding(
        key: ValueKey<String>('message-composer-${widget.destinationId}'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
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
                          const SingleActivator(LogicalKeyboardKey.enter): () {
                            unawaited(_submit());
                          },
                          const SingleActivator(
                            LogicalKeyboardKey.enter,
                            shift: true,
                          ): _insertNewLine,
                          const SingleActivator(
                            LogicalKeyboardKey.numpadEnter,
                          ): () {
                            unawaited(_submit());
                          },
                          const SingleActivator(
                            LogicalKeyboardKey.numpadEnter,
                            shift: true,
                          ): _insertNewLine,
                        },
                        child: TextField(
                          key: ValueKey<String>(
                            'message-input-${widget.destinationId}',
                          ),
                          controller: _controller,
                          focusNode: _focusNode,
                          readOnly: _sending,
                          minLines: 1,
                          maxLines: 6,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
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
                        onPressed: _canSend ? () => unawaited(_submit()) : null,
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
    );
  }
}
