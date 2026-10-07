import 'package:flutter/widgets.dart';

/// Shared layout and typography tokens.
///
/// The UI grew page by page, so paddings (6/8/10/12/14) and font sizes
/// (11/11.5/12/12.5/13/13.5) drifted apart. New and edited screens use these
/// tokens instead of hard-coded numbers, which keeps spacing and text
/// hierarchy consistent without changing the look from one release to the
/// next. The values are the ones the app already uses most often.
class Insets {
  Insets._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;

  /// Horizontal page padding used by every scrollable list.
  static const EdgeInsets page = EdgeInsets.fromLTRB(16, 6, 16, 100);

  /// Bottom padding for scrollable pages so the floating action button never
  /// covers the last row.
  static const double listBottom = 100;
}

/// Font sizes for the text hierarchy: captions, body copy, and titles.
class FontSizes {
  FontSizes._();

  /// Smallest labels: helper text under a field, dense badges.
  static const double micro = 11;

  /// Secondary text: subtitles, list metadata.
  static const double caption = 11.5;

  /// Small body text.
  static const double small = 12;

  /// Default body text.
  static const double body = 13.5;

  /// Section titles and card headers.
  static const double title = 14;

  /// Prominent values inside cards.
  static const double value = 15;

  /// Screen and hero titles.
  static const double headline = 17;
}

/// Corner radii for cards, sheets, and fields.
class Radii {
  Radii._();

  static const double field = 14;
  static const double card = 20;
  static const double sheet = 22;
}

/// Shared animation durations; keeping them equal keeps motion coherent.
class Motion {
  Motion._();

  /// Expand/collapse of collapsible sections and inline panels.
  static const Duration expand = Duration(milliseconds: 180);

  /// Small state changes such as a floating action button sliding away.
  static const Duration quick = Duration(milliseconds: 200);
}
