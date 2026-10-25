import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/app/theme/app_theme.dart';

void main() {
  for (final ThemeData theme in [
    MattermostTheme.light(),
    MattermostTheme.dark(),
  ]) {
    test('defines the application type scale for ${theme.brightness}', () {
      final TextTheme text = theme.textTheme;
      for (final (TextStyle?, double, double) role in [
        (text.titleLarge, 22, 28),
        (text.titleMedium, 16, 24),
        (text.bodyLarge, 16, 24),
        (text.bodyMedium, 15, 22),
        (text.bodySmall, 12, 16),
        (text.labelLarge, 14, 20),
        (text.labelMedium, 12, 16),
      ]) {
        expect(role.$1!.fontSize, role.$2);
        expect(role.$1!.height! * role.$2, closeTo(role.$3, 0.001));
      }
    });
  }
}
