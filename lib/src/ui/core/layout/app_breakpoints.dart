abstract final class AppBreakpoints {
  /// Widths below this value use stacked panes and bottom navigation.
  static const double compact = 700;

  /// Widths at or above this value use the full large-screen composition.
  static const double expanded = 1120;

  /// Minimum content-pane width at which channel history and a 380px thread
  /// pane remain useful side by side.
  static const double sideThread = 800;
}
