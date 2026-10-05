import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/ui/theme.dart';

void main() {
  test('Chip and list-tile text have readable contrast in both themes', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final chips = theme.chipTheme;
      final chipBackground = chips.backgroundColor!;
      final selectedBackground = chips.selectedColor!;

      expect(
        _contrast(chips.labelStyle!.color!, chipBackground),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(chips.secondaryLabelStyle!.color!, selectedBackground),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(theme.listTileTheme.titleTextStyle!.color!, theme.cardColor),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(
          theme.listTileTheme.subtitleTextStyle!.color!,
          theme.cardColor,
        ),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  final lighter = math.max(a, b);
  final darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}
