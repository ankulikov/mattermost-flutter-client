import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A visible vertical rule with a larger drag and keyboard focus target.
class ResizablePaneDivider extends StatefulWidget {
  const ResizablePaneDivider({
    required this.label,
    required this.onResize,
    this.increaseDirection = 1,
    super.key,
  });

  final String label;
  final ValueChanged<double> onResize;
  final double increaseDirection;

  static const double width = 44;
  static const double keyboardStep = 20;

  @override
  State<ResizablePaneDivider> createState() => _ResizablePaneDividerState();
}

class _ResizablePaneDividerState extends State<ResizablePaneDivider> {
  double? _lastDragX;

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).dividerColor;
    return Semantics(
      label: widget.label,
      onIncrease: () => widget.onResize(
        ResizablePaneDivider.keyboardStep * widget.increaseDirection,
      ),
      onDecrease: () => widget.onResize(
        -ResizablePaneDivider.keyboardStep * widget.increaseDirection,
      ),
      child: Focus(
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onResize(-ResizablePaneDivider.keyboardStep);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            widget.onResize(ResizablePaneDivider.keyboardStep);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (BuildContext context) => MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => Focus.of(context).requestFocus(),
              onHorizontalDragDown: (DragDownDetails details) =>
                  _lastDragX = details.globalPosition.dx,
              onHorizontalDragUpdate: (DragUpdateDetails details) {
                final double? previousX = _lastDragX;
                _lastDragX = details.globalPosition.dx;
                widget.onResize(
                  previousX == null
                      ? details.delta.dx
                      : details.globalPosition.dx - previousX,
                );
              },
              onHorizontalDragEnd: (_) => _lastDragX = null,
              onHorizontalDragCancel: () => _lastDragX = null,
              child: SizedBox(
                width: ResizablePaneDivider.width,
                child: Center(child: VerticalDivider(width: 1, color: color)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
