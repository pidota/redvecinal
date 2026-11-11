import 'package:flutter/material.dart';

import 'rv_colors.dart';

abstract final class RvTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: RvColors.forestGreen,
      brightness: Brightness.light,
      primary: RvColors.forestGreen,
      secondary: RvColors.amber,
      surface: RvColors.surfaceWhite,
      onSurface: RvColors.textDark,
      error: RvColors.error,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: RvColors.warmBackground,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: RvColors.warmBackground,
        foregroundColor: RvColors.textDark,
      ),
      cardTheme: CardThemeData(
        color: RvColors.surfaceWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: RvColors.surfaceWhite,
        indicatorColor: RvColors.amber.withValues(alpha: 0.35),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontWeight: FontWeight.w600,
              color: RvColors.forestGreen,
              fontSize: 12,
            );
          }
          return const TextStyle(
            fontWeight: FontWeight.w500,
            color: RvColors.textMuted,
            fontSize: 12,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: RvColors.forestGreen,
          foregroundColor: RvColors.surfaceWhite,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: RvColors.forestGreen,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: RvColors.surfaceWhite,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: RvColors.textDark,
          height: 1.25,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: RvColors.textDark,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: RvColors.textDark,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: RvColors.textDark, height: 1.4),
        bodyMedium: TextStyle(fontSize: 14, color: RvColors.textMuted, height: 1.45),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}
