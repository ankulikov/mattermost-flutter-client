import 'package:flutter/material.dart';

/// A centered section label between matching theme-colored rules.
class MessageSectionDivider extends StatelessWidget {
  const MessageSectionDivider({
    required this.label,
    this.bottomSpacing = 14,
    super.key,
  });

  final String label;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: label,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomSpacing),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) => Row(
            children: <Widget>[
              Expanded(child: Divider(color: color)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    // Leave space for both rules and the label's side padding.
                    maxWidth: constraints.maxWidth > 40
                        ? constraints.maxWidth - 40
                        : 0,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: color),
                  ),
                ),
              ),
              Expanded(child: Divider(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
