import 'package:flutter/material.dart';

/// Mattermost-specific semantic text styles derived from the active theme.
///
/// These styles adjust the application's base typography. Flutter applies the
/// platform [TextScaler] afterwards, preserving the user's accessibility
/// preference.
extension MattermostTextTheme on TextTheme {
  static const double _contentFontScale = 15 / 14;

  /// Channel names in the navigation sidebar.
  TextStyle get channelName =>
      bodyMedium!.apply(fontSizeFactor: _contentFontScale);

  /// User-authored message content.
  TextStyle get messageBody =>
      bodyMedium!.apply(fontSizeFactor: _contentFontScale);
}
