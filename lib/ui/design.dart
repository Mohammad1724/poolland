import 'package:flutter/widgets.dart';

/// Shared layout and typography tokens.
///
/// Shared tokens keep spacing, type, and tap targets predictable across the
/// app. The scale uses a four-point spacing rhythm and readable defaults; dense
/// data can still opt into a smaller label when it is genuinely secondary.
class Insets {
  Insets._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  /// Horizontal page padding used by every scrollable list.
  static const EdgeInsets page = EdgeInsets.fromLTRB(16, 8, 16, 100);

  /// Bottom padding for scrollable pages so the floating action button never
  /// covers the last row.
  static const double listBottom = 100;
}

/// Font sizes for the text hierarchy: captions, body copy, and titles.
class FontSizes {
  FontSizes._();

  /// Smallest labels: helper text under a field, dense badges.
  static const double micro = 12;

  /// Secondary text: subtitles, list metadata.
  static const double caption = 12;

  /// Small body text.
  static const double small = 13;

  /// Default body text.
  static const double body = 14;

  /// Section titles and card headers.
  static const double title = 15;

  /// Prominent values inside cards.
  static const double value = 16;

  /// Screen and hero titles.
  static const double headline = 19;
}

/// Corner radii for cards, sheets, and fields.
class Radii {
  Radii._();

  static const double field = 14;
  static const double card = 20;
  static const double sheet = 22;
}

/// Minimum sizes for tappable controls.
///
/// Material's `compact` density shaves segmented buttons and dense icon
/// buttons down to roughly 32–36 logical pixels, which is below the ~44 that a
/// fingertip reliably hits. Screens ask for these values instead of shrinking
/// any further.
class Taps {
  Taps._();

  /// Minimum height of an interactive control; width stays as wide as the
  /// content needs.
  static const double minHeight = 44;

  /// Minimum side of a square icon button.
  static const double icon = 44;
}

/// Shared animation durations; keeping them equal keeps motion coherent.
class Motion {
  Motion._();

  /// Expand/collapse of collapsible sections and inline panels.
  static const Duration expand = Duration(milliseconds: 180);

  /// Small state changes such as a floating action button sliding away.
  static const Duration quick = Duration(milliseconds: 200);

  /// Respect the operating system's reduced-motion preference.
  static Duration adaptive(BuildContext context, Duration duration) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return reduceMotion ? Duration.zero : duration;
  }
}
