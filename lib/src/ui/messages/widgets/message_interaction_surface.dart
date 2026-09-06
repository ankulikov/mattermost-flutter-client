import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mattermost_flutter/src/ui/messages/message_actions_strings.dart';

/// Adapts a message row to touch and precise pointer interactions.
class MessageInteractionSurface extends StatefulWidget {
  const MessageInteractionSurface({
    required this.onOpenThread,
    required this.child,
    super.key,
  });

  final VoidCallback onOpenThread;
  final Widget child;

  @override
  State<MessageInteractionSurface> createState() =>
      _MessageInteractionSurfaceState();
}

class _MessageInteractionSurfaceState extends State<MessageInteractionSurface> {
  Timer? _touchHighlightTimer;
  int? _activeTouchPointer;
  bool _hovered = false;
  bool _touchHighlighted = false;

  void _handlePointerDown(PointerDownEvent event) {
    if (!_isTouch(event.kind)) return;
    _activeTouchPointer = event.pointer;
    _showTouchHighlight();
  }

  void _handlePointerEnd(PointerEvent event) {
    if (event.pointer != _activeTouchPointer) return;
    _activeTouchPointer = null;
    _hideTouchHighlightSoon();
  }

  void _showTouchHighlight() {
    _touchHighlightTimer?.cancel();
    if (!_touchHighlighted) setState(() => _touchHighlighted = true);
  }

  void _hideTouchHighlightSoon() {
    _touchHighlightTimer?.cancel();
    _touchHighlightTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _touchHighlighted = false);
    });
  }

  void _handleLongPress() {
    if (_activeTouchPointer == null) return;
    unawaited(HapticFeedback.lightImpact());
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (BuildContext context) => const _MessageActionsBottomSheet(),
      ),
    );
  }

  @override
  void dispose() {
    _touchHighlightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool highlighted = _hovered || _touchHighlighted;
    return Semantics(
      button: true,
      label: MessageActionsStrings.actions,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Listener(
          onPointerDown: _handlePointerDown,
          onPointerUp: _handlePointerEnd,
          onPointerCancel: _handlePointerEnd,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpenThread,
            onLongPress: _handleLongPress,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) =>
                  Stack(
                    children: <Widget>[
                      Container(
                        key: const ValueKey<String>('message-highlight'),
                        decoration: BoxDecoration(
                          color: highlighted
                              ? colors.primary.withValues(alpha: 0.10)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: widget.child,
                      ),
                      if (_hovered)
                        PositionedDirectional(
                          top: 0,
                          end: 8,
                          child: _QuickMessageActions(
                            compact: constraints.maxWidth < 420,
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
}

class _QuickMessageActions extends StatelessWidget {
  const _QuickMessageActions({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => Card(
    key: const ValueKey<String>('quick-message-actions'),
    elevation: 3,
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Semantics(
      label: MessageActionsStrings.actions,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final String emoji
              in compact
                  ? const <String>['👍']
                  : const <String>['👍', '😀', '✅'])
            _EmojiAction(emoji: emoji),
          IconButton(
            tooltip: MessageActionsStrings.addReaction,
            onPressed: _mockAction,
            icon: const Icon(Icons.add_reaction_outlined),
          ),
          if (!compact)
            IconButton(
              tooltip: MessageActionsStrings.save,
              onPressed: _mockAction,
              icon: const Icon(Icons.bookmark_border),
            ),
          IconButton(
            tooltip: MessageActionsStrings.reply,
            onPressed: _mockAction,
            icon: const Icon(Icons.reply),
          ),
          PopupMenuButton<_MessageAction>(
            key: const ValueKey<String>('more-message-actions'),
            tooltip: MessageActionsStrings.more,
            icon: const Icon(Icons.more_horiz),
            onSelected: (_) {},
            itemBuilder: (BuildContext context) => _menuItems(),
          ),
        ],
      ),
    ),
  );
}

class _EmojiAction extends StatelessWidget {
  const _EmojiAction({required this.emoji});

  final String emoji;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: emoji,
    onPressed: _mockAction,
    icon: Text(emoji, style: const TextStyle(fontSize: 20)),
  );
}

class _MessageActionsBottomSheet extends StatelessWidget {
  const _MessageActionsBottomSheet();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      child: ListView(
        key: const ValueKey<String>('message-actions-bottom-sheet'),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: <Widget>[
          Semantics(
            label: MessageActionsStrings.addReaction,
            child: Wrap(
              spacing: 4,
              children: <Widget>[
                for (final String emoji in const <String>[
                  '😂',
                  '👍',
                  '✅',
                  '🔥',
                  '❤️',
                ])
                  _EmojiAction(emoji: emoji),
                IconButton(
                  tooltip: MessageActionsStrings.addReaction,
                  onPressed: _mockAction,
                  icon: const Icon(Icons.add_reaction_outlined),
                ),
              ],
            ),
          ),
          const Divider(),
          for (final _MessageAction action in _bottomSheetActions)
            ListTile(
              leading: Icon(action.icon),
              title: Text(action.label),
              onTap: _mockAction,
              minTileHeight: 48,
            ),
        ],
      ),
    ),
  );
}

enum _MessageAction {
  reply(Icons.reply, MessageActionsStrings.reply),
  forward(Icons.forward, MessageActionsStrings.forward),
  follow(Icons.add_comment_outlined, MessageActionsStrings.followThread),
  unread(Icons.mark_chat_unread_outlined, MessageActionsStrings.markUnread),
  save(Icons.bookmark_border, MessageActionsStrings.save),
  remind(Icons.alarm_outlined, MessageActionsStrings.remindLater),
  pin(Icons.push_pin_outlined, MessageActionsStrings.pinToChannel),
  copyText(Icons.copy_outlined, MessageActionsStrings.copyText),
  copyLink(Icons.link, MessageActionsStrings.copyLink),
  edit(Icons.edit_outlined, MessageActionsStrings.edit),
  delete(Icons.delete_outline, MessageActionsStrings.delete);

  const _MessageAction(this.icon, this.label);

  final IconData icon;
  final String label;
}

const List<_MessageAction> _bottomSheetActions = <_MessageAction>[
  _MessageAction.reply,
  _MessageAction.follow,
  _MessageAction.unread,
  _MessageAction.remind,
  _MessageAction.copyLink,
  _MessageAction.save,
  _MessageAction.copyText,
  _MessageAction.pin,
];

List<PopupMenuEntry<_MessageAction>> _menuItems() =>
    <_MessageAction>[
          _MessageAction.reply,
          _MessageAction.forward,
          _MessageAction.follow,
          _MessageAction.unread,
          _MessageAction.save,
          _MessageAction.remind,
          _MessageAction.pin,
          _MessageAction.copyText,
          _MessageAction.copyLink,
          _MessageAction.edit,
          _MessageAction.delete,
        ]
        .map((action) {
          final bool destructive = action == _MessageAction.delete;
          return PopupMenuItem<_MessageAction>(
            value: action,
            child: Row(
              children: <Widget>[
                Icon(action.icon, color: destructive ? Colors.red : null),
                const SizedBox(width: 12),
                Text(
                  action.label,
                  style: destructive
                      ? const TextStyle(color: Colors.red)
                      : null,
                ),
              ],
            ),
          );
        })
        .toList(growable: false);

void _mockAction() {}

bool _isTouch(PointerDeviceKind kind) =>
    kind == PointerDeviceKind.touch ||
    kind == PointerDeviceKind.stylus ||
    kind == PointerDeviceKind.invertedStylus;
