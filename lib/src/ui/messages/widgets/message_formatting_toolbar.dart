import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_breakpoints.dart';
import 'package:mattermost_flutter/src/ui/messages/message_composer_strings.dart';

/// A formatting operation that an editor can apply to its current selection.
///
/// This intentionally describes only presentation intent. The editor owns the
/// pure Markdown transformation and the selection update.
enum MessageFormattingCommand {
  bold,
  italic,
  strike,
  heading,
  link,
  code,
  quote,
  bulletedList,
  orderedList,
}

/// Adaptive controls for Markdown formatting in a message editor.
///
/// On compact layouts, the less frequently used block controls are available
/// from an overflow menu. [onCommandSelected] receives only a command, keeping
/// this widget independent from an editor controller or its editing buffer.
class MessageFormattingToolbar extends StatelessWidget {
  const MessageFormattingToolbar({
    required this.activeCommands,
    required this.onCommandSelected,
    this.editorFocusNode,
    this.enabled = true,
    this.showAllCommands = false,
    super.key,
  });

  /// Commands that apply at the current editor selection.
  final Set<MessageFormattingCommand> activeCommands;

  /// Handles a command selected from the toolbar.
  final ValueChanged<MessageFormattingCommand> onCommandSelected;

  /// The editor focus restored after a pointer selection from this toolbar.
  ///
  /// A formatting operation should retain the text selection, so the editor
  /// passes its [FocusNode] here instead of allowing a toolbar control to keep
  /// focus after it is clicked.
  final FocusNode? editorFocusNode;

  /// Whether formatting commands are available.
  final bool enabled;

  /// Whether every command remains visible instead of using an overflow menu.
  ///
  /// The full message editor uses this mode and lets the controls wrap when
  /// horizontal space is constrained.
  final bool showAllCommands;

  void _selectCommand(MessageFormattingCommand command) {
    if (!enabled) return;
    onCommandSelected(command);
    final FocusNode? focusNode = editorFocusNode;
    if (focusNode != null && focusNode.canRequestFocus) {
      focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final bool compact = constraints.maxWidth < AppBreakpoints.compact;
      final List<Widget> controls = <Widget>[
        _commandButton(MessageFormattingCommand.bold),
        _commandButton(MessageFormattingCommand.italic),
        _commandButton(MessageFormattingCommand.strike),
        _commandButton(MessageFormattingCommand.heading),
        if (showAllCommands || !compact) ...<Widget>[
          const ExcludeSemantics(
            child: SizedBox(height: 24, child: VerticalDivider(width: 16)),
          ),
          _commandButton(MessageFormattingCommand.link),
          _commandButton(MessageFormattingCommand.code),
          _commandButton(MessageFormattingCommand.quote),
          _commandButton(MessageFormattingCommand.bulletedList),
          _commandButton(MessageFormattingCommand.orderedList),
        ] else
          _overflowButton(),
      ];
      return Semantics(
        container: true,
        label: MessageComposerStrings.formattingToolbar,
        child: showAllCommands
            ? Wrap(children: controls)
            : SizedBox(
                height: 48,
                child: Row(mainAxisSize: MainAxisSize.min, children: controls),
              ),
      );
    },
  );

  Widget _commandButton(MessageFormattingCommand command) {
    final _FormattingControl control = _FormattingControl.forCommand(command);
    final bool active = activeCommands.contains(command);
    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: Semantics(
        key: ValueKey<String>('message-formatting-${command.name}'),
        button: true,
        toggled: active,
        enabled: enabled,
        label: control.label,
        child: Tooltip(
          message: control.label,
          excludeFromSemantics: true,
          child: IconButton(
            isSelected: active,
            tooltip: control.label,
            onPressed: enabled ? () => _selectCommand(command) : null,
            icon: Icon(control.icon),
          ),
        ),
      ),
    );
  }

  Widget _overflowButton() => Focus(
    canRequestFocus: false,
    descendantsAreFocusable: false,
    child: Semantics(
      key: const ValueKey<String>('message-formatting-overflow'),
      button: true,
      enabled: enabled,
      label: MessageComposerStrings.moreFormatting,
      child: Tooltip(
        message: MessageComposerStrings.moreFormatting,
        excludeFromSemantics: true,
        child: PopupMenuButton<MessageFormattingCommand>(
          tooltip: MessageComposerStrings.moreFormatting,
          enabled: enabled,
          icon: const Icon(Icons.more_horiz),
          onSelected: _selectCommand,
          itemBuilder: (BuildContext context) => _overflowCommands
              .map(
                (MessageFormattingCommand command) =>
                    CheckedPopupMenuItem<MessageFormattingCommand>(
                      key: ValueKey<String>(
                        'message-formatting-menu-${command.name}',
                      ),
                      value: command,
                      checked: activeCommands.contains(command),
                      child: Text(_FormattingControl.forCommand(command).label),
                    ),
              )
              .toList(growable: false),
        ),
      ),
    ),
  );
}

const List<MessageFormattingCommand> _overflowCommands =
    <MessageFormattingCommand>[
      MessageFormattingCommand.link,
      MessageFormattingCommand.code,
      MessageFormattingCommand.quote,
      MessageFormattingCommand.bulletedList,
      MessageFormattingCommand.orderedList,
    ];

final class _FormattingControl {
  const _FormattingControl(this.label, this.icon);

  factory _FormattingControl.forCommand(MessageFormattingCommand command) =>
      switch (command) {
        MessageFormattingCommand.bold => const _FormattingControl(
          MessageComposerStrings.formatBold,
          Icons.format_bold,
        ),
        MessageFormattingCommand.italic => const _FormattingControl(
          MessageComposerStrings.formatItalic,
          Icons.format_italic,
        ),
        MessageFormattingCommand.strike => const _FormattingControl(
          MessageComposerStrings.formatStrike,
          Icons.format_strikethrough,
        ),
        MessageFormattingCommand.heading => const _FormattingControl(
          MessageComposerStrings.formatHeading,
          Icons.title,
        ),
        MessageFormattingCommand.link => const _FormattingControl(
          MessageComposerStrings.formatLink,
          Icons.link,
        ),
        MessageFormattingCommand.code => const _FormattingControl(
          MessageComposerStrings.formatCode,
          Icons.code,
        ),
        MessageFormattingCommand.quote => const _FormattingControl(
          MessageComposerStrings.formatQuote,
          Icons.format_quote,
        ),
        MessageFormattingCommand.bulletedList => const _FormattingControl(
          MessageComposerStrings.formatBulletedList,
          Icons.format_list_bulleted,
        ),
        MessageFormattingCommand.orderedList => const _FormattingControl(
          MessageComposerStrings.formatOrderedList,
          Icons.format_list_numbered,
        ),
      };

  final String label;
  final IconData icon;
}
