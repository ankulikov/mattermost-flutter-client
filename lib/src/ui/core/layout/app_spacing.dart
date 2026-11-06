import 'package:flutter/widgets.dart';

abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

abstract final class AppLayout {
  static const double sidePaneWidth = 380;

  /// Compact sidebar rows retain a minimum 40 px interactive target.
  static const double sidebarRowMinHeight = 40;
  static const double sidebarMinWidth = 200;
  static const double sidebarMaxWidth = 500;
  static const double sidebarItemInset = AppSpacing.lg;
  static const double sidebarLeadingIconInset = AppSpacing.xxxl;
  static const double sidebarSearchIconSlotWidth =
      sidebarLeadingIconInset - sidebarItemInset + AppSpacing.xxl;
  static const double sidebarSearchMinHeight =
      sidebarRowMinHeight + AppSpacing.sm;

  /// Shared horizontal grid for the search, Threads, and channel rows.
  static const EdgeInsets sidebarSearchPadding = EdgeInsets.fromLTRB(
    sidebarItemInset,
    AppSpacing.md,
    sidebarItemInset,
    AppSpacing.xs,
  );
  static const EdgeInsets sidebarBannerPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.xs,
  );
  static const EdgeInsets sidebarSearchIconPadding = EdgeInsets.only(
    left: sidebarLeadingIconInset - sidebarItemInset,
  );
  static const BoxConstraints sidebarSearchPrefixIconConstraints =
      BoxConstraints(minWidth: sidebarSearchIconSlotWidth);
  static const BoxConstraints sidebarSearchConstraints = BoxConstraints(
    minHeight: sidebarSearchMinHeight,
  );
  static const double readableContentWidth = 760;
  static const double compactPageGutter = AppSpacing.sm;
  static const double expandedPageGutter = AppSpacing.xxl;
  static const double cardPadding = AppSpacing.lg;
  static const double messageAvatarGap = AppSpacing.sm;
}
