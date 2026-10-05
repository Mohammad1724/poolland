import 'package:flutter/material.dart';

/// Light and dark app themes using the Vazirmatn font
class AppTheme {
  AppTheme._();

  static const seed = Color(0xFF0EA5A4); // Teal
  static const revenue = Color(0xFF16A34A);
  static const expense = Color(0xFFE11D48);
  static const warning = Color(0xFFF59E0B);
  static const receivable = Color(0xFF0F766E); // Receivable
  static const payable = Color(0xFF2563EB); // Payable
  static const cash = Color(0xFF7C3AED);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    return _base(scheme, const Color(0xFFF4F6FA), Colors.white);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    return _base(scheme, const Color(0xFF0B1220), const Color(0xFF141D31));
  }

  static ThemeData _base(ColorScheme scheme, Color bg, Color card) {
    final isDark = scheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Vazirmatn',
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      cardColor: card,
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isDark ? const Color(0xFF243149) : const Color(0xFFE6EAF2),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Vazirmatn',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontFamily: 'Vazirmatn', fontSize: 11, fontWeight: FontWeight.w600),
        ),
        height: 66,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1B2540) : const Color(0xFFF5F7FB),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: isDark ? const Color(0xFF2A3A5A) : const Color(0xFFE1E6F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: isDark ? const Color(0xFF2A3A5A) : const Color(0xFFE1E6F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: seed, width: 1.4),
        ),
        labelStyle: const TextStyle(fontFamily: 'Vazirmatn', fontSize: 13),
        hintStyle: TextStyle(
            fontFamily: 'Vazirmatn',
            fontSize: 13,
            color: scheme.onSurface.withValues(alpha: 0.45)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: scheme.primaryContainer,
        secondarySelectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(
          fontFamily: 'Vazirmatn',
          fontSize: 12,
          color: scheme.onSurface,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: 'Vazirmatn',
          fontSize: 12,
          color: scheme.onPrimaryContainer,
        ),
        checkmarkColor: scheme.onPrimaryContainer,
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: isDark ? const Color(0xFF2A3A5A) : const Color(0xFFE1E6F0)),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF243149) : const Color(0xFFE9EDF5),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF23304A) : const Color(0xFF1F2937),
        contentTextStyle: const TextStyle(fontFamily: 'Vazirmatn', fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(
              fontFamily: 'Vazirmatn', fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: isDark ? const Color(0xFF2A3A5A) : const Color(0xFFDCE2EE)),
          textStyle: const TextStyle(
              fontFamily: 'Vazirmatn', fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(
              fontFamily: 'Vazirmatn', fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: TextStyle(
          fontFamily: 'Vazirmatn',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: 'Vazirmatn',
          fontSize: 12,
          color: scheme.onSurfaceVariant,
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(
            fontFamily: 'Vazirmatn',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface),
        contentTextStyle: TextStyle(
            fontFamily: 'Vazirmatn', fontSize: 13, color: scheme.onSurface),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: seed,
        foregroundColor: Colors.white,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? scheme.onPrimaryContainer
                  : scheme.onSurface),
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontFamily: 'Vazirmatn', fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
