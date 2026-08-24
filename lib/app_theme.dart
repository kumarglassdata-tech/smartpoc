import 'package:flutter/material.dart';

// Palette lifted from the "Myna App Redesign" mockup (light) and from dark
// shades present but unused in that same mockup (dark) - every screen reads
// colors through these getters instead of a literal Color(0x...), so calling
// AppColors.setDark() from one place (buildAppTheme) re-themes the whole app.
class AppColors {
  AppColors._();

  static bool _isDark = false;
  static bool get isDark => _isDark;
  static void setDark(bool value) => _isDark = value;

  static Color get background => _isDark ? const Color(0xFF171512) : const Color(0xFFFBF6EC);
  static Color get surface => _isDark ? const Color(0xFF2A2420) : const Color(0xFFFFFFFF);
  static Color get surfaceMuted => _isDark ? const Color(0xFF23201C) : const Color(0xFFF5ECDC);
  static Color get border => _isDark ? const Color(0xFF3A342C) : const Color(0xFFEAE0CF);

  static Color get textPrimary => _isDark ? const Color(0xFFFBF6EC) : const Color(0xFF23201C);
  static Color get textSecondary => _isDark ? const Color(0xFFA69C8C) : const Color(0xFF8B7F6E);

  static Color get accent => const Color(0xFFE8963C);
  static Color get accentStrong => _isDark ? const Color(0xFFF0AC5E) : const Color(0xFFC97B2E);
  static Color get accentTint => _isDark ? const Color(0xFF3A2E1C) : const Color(0xFFFBE4C4);

  static Color get dark => _isDark ? const Color(0xFF100E0C) : const Color(0xFF23201C);

  static Color get success => const Color(0xFF4C9A6A);
  static Color get successTint => _isDark ? const Color(0xFF1E3327) : const Color(0xFFE4F3EA);

  static Color get danger => _isDark ? const Color(0xFFE2665A) : const Color(0xFFD9614F);
  static Color get dangerTint => _isDark ? const Color(0xFF3A211D) : const Color(0xFFFBE7E4);
}

ThemeData buildAppTheme({required bool isDark}) {
  AppColors.setDark(isDark);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: isDark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    secondary: AppColors.accentStrong,
    onSecondary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    error: AppColors.danger,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: isDark ? Brightness.dark : Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Roboto',
    textTheme: TextTheme(
      headlineSmall: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: AppColors.textPrimary),
      bodyMedium: TextStyle(color: AppColors.textPrimary),
      bodySmall: TextStyle(color: AppColors.textSecondary),
      labelLarge: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: AppColors.border)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: TextStyle(color: AppColors.textSecondary),
      labelStyle: TextStyle(color: AppColors.textPrimary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.accent, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.white : AppColors.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? AppColors.accent : AppColors.border,
      ),
    ),
    dividerTheme: DividerThemeData(color: AppColors.border, space: 1),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: AppColors.textSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
  );
}
