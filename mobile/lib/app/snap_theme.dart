// MaterialState aliases remain the compatibility API for Flutter 3.19, whose
// bundled Dart SDK is 3.3. They are deprecated, but still supported by newer
// Flutter releases after the WidgetState rename in Flutter 3.22.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

abstract final class SnapColors {
  static const electricBlue = Color(0xFF087CFA);
  static const success = Color(0xFF20C875);
  static const warning = Color(0xFFFFB020);
  static const lightBackground = Color(0xFFF7F7F8);
  static const darkBackground = Color(0xFF050607);
  static const darkSurface = Color(0xFF111315);
}

abstract final class SnapTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: SnapColors.electricBlue,
      brightness: brightness,
    ).copyWith(
      primary: SnapColors.electricBlue,
      secondary: SnapColors.electricBlue,
      error: SnapColors.warning,
      onError: const Color(0xFF17130A),
      errorContainer:
          isDark ? const Color(0xFF382A06) : const Color(0xFFFFE8B0),
      onErrorContainer:
          isDark ? const Color(0xFFFFD56A) : const Color(0xFF4A3400),
      surface: isDark ? SnapColors.darkSurface : Colors.white,
    );

    final base = ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor:
          isDark ? SnapColors.darkBackground : SnapColors.lightBackground,
      fontFamilyFallback: const <String>['Apple SD Gothic Neo', 'Noto Sans KR'],
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withOpacity(0.55),
        thickness: 0.7,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SnapColors.electricBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF0B0D0F) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: SnapColors.electricBlue,
            width: 1.5,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor:
            isDark ? SnapColors.darkBackground : SnapColors.lightBackground,
        indicatorColor: Colors.transparent,
        labelTextStyle: MaterialStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(MaterialState.selected)
                ? SnapColors.electricBlue
                : scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: states.contains(MaterialState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
        iconTheme: MaterialStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(MaterialState.selected)
                ? SnapColors.electricBlue
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
