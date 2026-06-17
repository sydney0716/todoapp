import 'package:flutter/material.dart';

import 'settings_controller.dart';

const plannerLightBackground = Color(0xFFF6EAD8);
const plannerLightTopPanel = Color(0xFFF8EEDF);
const plannerLightSurface = Color(0xFFFFFCF5);
const plannerLightKey = Color(0xFF8B5E34);
const plannerLightSub = Color(0xFF2D2A26);

const plannerDarkBackground = Color(0xFF1F1B17);
const plannerDarkSurface = Color(0xFF2A241E);
const plannerDarkKey = Color(0xFFD6B07C);
const plannerDarkSub = Color(0xFFEDE2D1);
const plannerDarkLine = Color(0xFF4A3E32);

Color plannerTopPanelColor(ThemeData theme) {
  return theme.brightness == Brightness.light
      ? plannerLightTopPanel
      : theme.colorScheme.surface;
}

ThemeMode flutterThemeMode(AppThemeMode mode) {
  switch (mode) {
    case AppThemeMode.dark:
      return ThemeMode.dark;
    case AppThemeMode.light:
      return ThemeMode.light;
    case AppThemeMode.followSystem:
      return ThemeMode.system;
  }
}

ThemeData buildLightTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: plannerLightKey,
      onPrimary: plannerLightSurface,
      primaryContainer: plannerLightKey,
      onPrimaryContainer: plannerLightSurface,
      secondary: plannerLightSub,
      onSecondary: plannerLightSurface,
      secondaryContainer: plannerLightSurface,
      onSecondaryContainer: plannerLightSub,
      tertiary: plannerLightSub,
      onTertiary: plannerLightSurface,
      tertiaryContainer: plannerLightSurface,
      onTertiaryContainer: plannerLightSub,
      error: plannerLightKey,
      onError: plannerLightSurface,
      errorContainer: plannerLightSurface,
      onErrorContainer: plannerLightSub,
      surface: plannerLightSurface,
      onSurface: plannerLightSub,
      surfaceContainerHighest: plannerLightBackground,
      onSurfaceVariant: plannerLightSub,
      outline: plannerLightKey,
      outlineVariant: plannerLightKey,
    ),
    scaffoldBackgroundColor: plannerLightBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: plannerLightTopPanel,
      surfaceTintColor: Colors.transparent,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
    ),
  );
}

ThemeData buildDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: plannerDarkKey,
      onPrimary: plannerDarkBackground,
      primaryContainer: plannerDarkKey,
      onPrimaryContainer: plannerDarkBackground,
      secondary: plannerDarkKey,
      onSecondary: plannerDarkBackground,
      secondaryContainer: plannerDarkSurface,
      onSecondaryContainer: plannerDarkSub,
      tertiary: plannerDarkSub,
      onTertiary: plannerDarkBackground,
      tertiaryContainer: plannerDarkSurface,
      onTertiaryContainer: plannerDarkSub,
      error: plannerDarkKey,
      onError: plannerDarkBackground,
      errorContainer: plannerDarkSurface,
      onErrorContainer: plannerDarkSub,
      surface: plannerDarkSurface,
      onSurface: plannerDarkSub,
      surfaceContainerHighest: plannerDarkSurface,
      onSurfaceVariant: plannerDarkSub,
      outline: plannerDarkLine,
      outlineVariant: plannerDarkLine,
    ),
    scaffoldBackgroundColor: plannerDarkBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: plannerDarkSurface,
      surfaceTintColor: Colors.transparent,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
    ),
  );
}
