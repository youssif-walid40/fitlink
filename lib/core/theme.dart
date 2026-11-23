import 'package:flutter/material.dart';

/// Colours taken from the FitLink wireframes: warm off-white background,
/// near-black primary actions and a lime accent.
class AppColors {
  AppColors._();
  static const ink = Color(0xFF111111);
  static const lime = Color(0xFFD9F26B);
  static const limeSoft = Color(0xFFE9F7B8);
  static const bgLight = Color(0xFFF3F3EF);
  static const surfaceLight = Colors.white;
  static const borderLight = Color(0xFFE4E4DE);
  static const muted = Color(0xFF6E6E6A);
  static const bgDark = Color(0xFF0E0E0E);
  static const surfaceDark = Color(0xFF1A1A1A);
  static const borderDark = Color(0xFF2C2C2C);
  static const success = Color(0xFF2E9E5B);
  static const warning = Color(0xFFE0A100);
  static const danger = Color(0xFFD64545);
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? AppColors.lime : AppColors.ink,
    onPrimary: dark ? AppColors.ink : Colors.white,
    secondary: AppColors.lime,
    onSecondary: AppColors.ink,
    error: AppColors.danger,
    onError: Colors.white,
    surface: dark ? AppColors.surfaceDark : AppColors.surfaceLight,
    onSurface: dark ? Colors.white : AppColors.ink,
    surfaceContainerHighest: dark ? const Color(0xFF242424) : const Color(0xFFEDEDE7),
    outline: dark ? AppColors.borderDark : AppColors.borderLight,
    onSurfaceVariant: dark ? const Color(0xFFB0B0AA) : AppColors.muted,
  );

  final radius = BorderRadius.circular(14);
  final border = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: scheme.outline),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? AppColors.bgDark : AppColors.bgLight,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? AppColors.bgDark : AppColors.bgLight,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      errorBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.danger),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 50),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 50),
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: scheme.outline),
      selectedColor: AppColors.lime,
      checkmarkColor: AppColors.ink,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: dark ? AppColors.lime.withValues(alpha: 0.25) : AppColors.limeSoft,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: DividerThemeData(color: scheme.outline, space: 1),
  );
}
