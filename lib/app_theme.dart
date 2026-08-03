import 'package:flutter/material.dart';

import 'package:sitemark/shared/theme/accent_swatches.dart';

/// Builds a light [ColorScheme] from [seedColor], optionally preferring a
/// platform-supplied [dynamicColor] palette.
ColorScheme _buildLightScheme(Color seedColor, {ColorScheme? dynamicColor}) {
  return dynamicColor ??
      ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.light,
      );
}

/// Builds a dark [ColorScheme] from [seedColor], optionally preferring a
/// platform-supplied [dynamicColor] palette.
ColorScheme _buildDarkScheme(Color seedColor, {ColorScheme? dynamicColor}) {
  return dynamicColor ??
      ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.dark,
      );
}

/// Builds a complete [ThemeData] from the given [colorScheme].
///
/// When [isDark] is `true` the input-decoration border is omitted to match
/// the original per-mode styling.
ThemeData _buildThemeData(ColorScheme colorScheme, {bool isDark = false}) {
  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    inputDecorationTheme: isDark
        ? null
        : const InputDecorationTheme(border: OutlineInputBorder()),
  );
}

/// Builds the light theme for the app.
///
/// [seedColor] is the brand seed colour. Pass a [dynamicColor] from
/// [DynamicColorBuilder] to use the platform palette instead.
ThemeData buildLightTheme({
  required Color seedColor,
  ColorScheme? dynamicColor,
}) {
  final scheme = _buildLightScheme(seedColor, dynamicColor: dynamicColor);
  return _buildThemeData(scheme);
}

/// Builds the dark theme for the app.
///
/// [seedColor] is the brand seed colour. Pass a [dynamicColor] from
/// [DynamicColorBuilder] to use the platform palette instead.
ThemeData buildDarkTheme({
  required Color seedColor,
  ColorScheme? dynamicColor,
}) {
  final scheme = _buildDarkScheme(seedColor, dynamicColor: dynamicColor);
  return _buildThemeData(scheme, isDark: true);
}