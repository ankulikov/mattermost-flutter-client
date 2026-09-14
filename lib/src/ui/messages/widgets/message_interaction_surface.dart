import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mattermost_flutter/src/domain/repositories/emoji_repository.dart';
import 'package:mattermost_flutter/src/ui/messages/message_actions_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/emoji_picker.dart';

/// Shares post-level touch interactions with an interactive Markdown body.
///
/// [MattermostMarkdown] consumes this scope only when it is rendered inside a
/// [MessageInteractionSurface]. Its touch-only recognizers call these callbacks
/// so that the local [SelectionArea] does not win the gesture arena. Markdown
/// rendered without this scope remains independently selectable.
class MessageInteractionScope extends InheritedWidget {
  const MessageInteractionScope({
    required this.onTouchTap,
    required this.onTouchLongPressStart,
    required super.child,
    super.key,
  });

  /// Opens the thread when touch tap wins over Markdown selection.
  ///
  /// This is deliberately non-null even when the row has no open-thread action:
  /// the no-op still prevents touch selection in an already open thread.
  final VoidCallback onTouchTap;

  /// Starts a recognized touch long press and opens post actions.
  final VoidCallback onTouchLongPressStart;

  static MessageInteractionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MessageInteractionScope>();

  static MessageInteractionScope of(BuildContext context) {
    final MessageInteractionScope? scope = maybeOf(context);
    assert(scope != null, 'No MessageInteractionScope found in context.');
    return scope!;
  }

  @override
  bool updateShouldNotify(MessageInteractionScope oldWidget) =>
      onTouchTap != oldWidget.onTouchTap ||
      onTouchLongPressStart != oldWidget.onTouchLongPressStart;
}

/// Adapts a message row to touch and precise pointer interactions.
class MessageInteractionSurface extends StatefulWidget {
  const MessageInteractionSurface({
    required this.onOpenThread,
    required this.child,
    this.onToggleReaction,
    this.emojiRepositoryFactory,
    this.accountId = '',
    super.key,
  });

  final VoidCallback? onOpenThread;
  final Widget child;
  final Future<bool> Function(String emojiName)? onToggleReaction;
  final CustomEmojiRepository Function()? emojiRepositoryFactory;
  final String accountId;

  @override
  State<MessageInteractionSurface> createState() =>
      _MessageInteractionSurfaceState();
}

class _MessageInteractionSurfaceState extends State<MessageInteractionSurface> {
  final OverlayPortalController _quickActionsController =
      OverlayPortalController();
  Timer? _hoverExitTimer;
  bool _messageHovered = false;
  bool _quickActionsHovered = false;
  bool _touchHighlighted = false;
  bool _actionsSheetOpen = false;

  bool get _hovered => _messageHovered || _quickActionsHovered;

  void _handleMessageHover(bool hovered) {
    _hoverExitTimer?.cancel();
    setState(() => _messageHovered = hovered);
    if (hovered) {
      _quickActionsController.show();
    } else {
      _hideQuickActionsSoon();
    }
  }

  void _handleQuickActionsHover(bool hovered) {
    _hoverExitTimer?.cancel();
    setState(() => _quickActionsHovered = hovered);
    if (!hovered) _hideQuickActionsSoon();
  }

  void _hideQuickActionsSoon() {
    _hoverExitTimer = Timer(Duration.zero, () {
      if (mounted && !_hovered) _quickActionsController.hide();
    });
  }

  void _openThread() {
    widget.onOpenThread?.call();
  }

  void _handleTouchLongPressStart() {
    if (!_touchHighlighted) setState(() => _touchHighlighted = true);
    unawaited(_showActionsSheet());
  }

  void _handleTouchLongPressEnd() {
    if (_touchHighlighted && mounted) {
      setState(() => _touchHighlighted = false);
    }
  }

  void _handleTouchPointerUp(PointerUpEvent event) {
    if (_isTouchLike(event.kind)) _handleTouchLongPressEnd();
  }

  void _handleTouchPointerCancel(PointerCancelEvent event) {
    if (_isTouchLike(event.kind) && !_actionsSheetOpen) {
      _handleTouchLongPressEnd();
    }
  }

  Future<void> _showActionsSheet() async {
    if (_actionsSheetOpen || !mounted) return;
    _actionsSheetOpen = true;
    try {
      unawaited(HapticFeedback.lightImpact());
      final _MessageSheetResult? result =
          await showModalBottomSheet<_MessageSheetResult>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (BuildContext context) =>
                const _MessageActionsBottomSheet(),
          );
      if (!mounted || result == null) return;
      if (result.openPicker) {
        await _openTouchPicker();
      } else if (result.emojiName case final String name) {
        await _submitReaction(name);
      }
    } finally {
      _actionsSheetOpen = false;
      _handleTouchLongPressEnd();
    }
  }

  Future<void> _openTouchPicker() async {
    final CustomEmojiRepository? repository = widget.emojiRepositoryFactory
        ?.call();
    if (repository == null || widget.accountId.isEmpty) return;
    final String? selected = await showEmojiPickerBottomSheet(
      context: context,
      repository: repository,
      accountId: widget.accountId,
    );
    if (selected != null && mounted) await _submitReaction(selected);
  }

  Future<void> _openPointerPicker(BuildContext anchorContext) async {
    final CustomEmojiRepository? repository = widget.emojiRepositoryFactory
        ?.call();
    if (repository == null || widget.accountId.isEmpty) return;
    final RenderBox? box = anchorContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final Offset origin = box.localToGlobal(Offset.zero);
    final String? selected = await showEmojiPickerPopover(
      context: context,
      anchor: origin & box.size,
      repository: repository,
      accountId: widget.accountId,
    );
    if (selected != null && mounted) await _submitReaction(selected);
  }

  Future<void> _submitReaction(String emojiName) async {
    final Future<bool> Function(String emojiName)? toggle =
        widget.onToggleReaction;
    if (toggle == null) return;
    final bool succeeded = await toggle(emojiName);
    final CustomEmojiRepository? repository = widget.emojiRepositoryFactory
        ?.call();
    if (!succeeded || repository == null || widget.accountId.isEmpty) return;
    try {
      await repository.rememberRecent(
        accountId: widget.accountId,
        emojiName: emojiName,
      );
    } on Object {
      // Reaction success is authoritative; MRU persistence is best effort.
    }
  }

  @override
  void dispose() {
    _hoverExitTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool highlighted = _hovered || _touchHighlighted;
    return Semantics(
      button: widget.onOpenThread != null,
      label: MessageActionsStrings.actions,
      onTap: widget.onOpenThread == null ? null : _openThread,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool isLeftToRight =
              Directionality.of(context) == TextDirection.ltr;
          return OverlayPortal.overlayChildLayoutBuilder(
            controller: _quickActionsController,
            overlayChildBuilder:
                (BuildContext context, OverlayChildLayoutInfo info) {
                  final Offset anchor = MatrixUtils.transformPoint(
                    info.childPaintTransform,
                    Offset(isLeftToRight ? info.childSize.width - 8 : 8, 0),
                  );
                  return Positioned(
                    top: anchor.dy,
                    left: isLeftToRight ? null : anchor.dx,
                    right: isLeftToRight
                        ? info.overlaySize.width - anchor.dx
                        : null,
                    child: MouseRegion(
                      onEnter: (_) => _handleQuickActionsHover(true),
                      onExit: (_) => _handleQuickActionsHover(false),
                      child: _QuickMessageActions(
                        compact: constraints.maxWidth < 420,
                        onEmojiSelected: _submitReaction,
                        onOpenPicker: _openPointerPicker,
                      ),
                    ),
                  );
                },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => _handleMessageHover(true),
              onExit: (_) => _handleMessageHover(false),
              child: Listener(
                onPointerUp: _handleTouchPointerUp,
                onPointerCancel: _handleTouchPointerCancel,
                child: RawGestureDetector(
                  behavior: HitTestBehavior.opaque,
                  gestures: <Type, GestureRecognizerFactory>{
                    TapGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          TapGestureRecognizer
                        >(TapGestureRecognizer.new, (
                          TapGestureRecognizer recognizer,
                        ) {
                          recognizer.onTap = _openThread;
                        }),
                    LongPressGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          LongPressGestureRecognizer
                        >(
                          () => LongPressGestureRecognizer(
                            supportedDevices: _touchLikePointerKinds,
                          ),
                          (LongPressGestureRecognizer recognizer) {
                            recognizer.onLongPressStart = (_) =>
                                _handleTouchLongPressStart();
                          },
                        ),
                  },
                  child: Container(
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
                    child: MessageInteractionScope(
                      onTouchTap: _openThread,
                      onTouchLongPressStart: _handleTouchLongPressStart,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

const Set<PointerDeviceKind> _touchLikePointerKinds = <PointerDeviceKind>{
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
};

bool _isTouchLike(PointerDeviceKind kind) =>
    _touchLikePointerKinds.contains(kind);

class _QuickMessageActions extends StatelessWidget {
  const _QuickMessageActions({
    required this.compact,
    required this.onEmojiSelected,
    required this.onOpenPicker,
  });

  final bool compact;
  final Future<void> Function(String) onEmojiSelected;
  final Future<void> Function(BuildContext) onOpenPicker;

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
            _EmojiAction(
              emoji: emoji,
              onPressed: () => unawaited(onEmojiSelected(_emojiName(emoji))),
            ),
          Builder(
            builder: (BuildContext anchorContext) => IconButton(
              tooltip: MessageActionsStrings.addReaction,
              onPressed: () => unawaited(onOpenPicker(anchorContext)),
              icon: const Icon(Icons.add_reaction_outlined),
            ),
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
  const _EmojiAction({required this.emoji, required this.onPressed});

  final String emoji;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: emoji,
    onPressed: onPressed,
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
                  _EmojiAction(
                    emoji: emoji,
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(_MessageSheetResult.emoji(_emojiName(emoji))),
                  ),
                IconButton(
                  tooltip: MessageActionsStrings.addReaction,
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(const _MessageSheetResult.picker()),
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

final class _MessageSheetResult {
  const _MessageSheetResult.emoji(this.emojiName) : openPicker = false;

  const _MessageSheetResult.picker() : emojiName = null, openPicker = true;

  final String? emojiName;
  final bool openPicker;
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

String _emojiName(String emoji) => switch (emoji) {
  '👍' => 'thumbsup',
  '😀' => 'grinning',
  '✅' => 'white_check_mark',
  '😂' => 'joy',
  '🔥' => 'fire',
  '❤️' => 'heart',
  _ => emoji,
};
