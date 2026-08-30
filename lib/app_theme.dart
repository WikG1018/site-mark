import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Builds a light [ColorScheme] from [seedColor], optionally preferring a
/// platform-supplied [dynamicColor] palette.
ColorScheme _buildLightScheme(Color seedColor, {ColorScheme? dynamicColor}) {
  return dynamicColor ??
      ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.light);
}

/// Builds a dark [ColorScheme] from [seedColor], optionally preferring a
/// platform-supplied [dynamicColor] palette.
ColorScheme _buildDarkScheme(Color seedColor, {ColorScheme? dynamicColor}) {
  return dynamicColor ??
      ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark);
}

/// Builds a complete [ThemeData] from the given [colorScheme].
ThemeData _buildThemeData(ColorScheme colorScheme) {
  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    // Cupertino buttons dim on press; ink splashes are not part of the iOS
    // press vocabulary. Android keeps the M3 InkSparkle.
    splashFactory: defaultTargetPlatform == TargetPlatform.iOS
        ? NoSplash.splashFactory
        : InkSparkle.splashFactory,
    scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,
    cardTheme: CardThemeData(
      color: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: .72),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
    ),
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
  return _buildThemeData(scheme);
}

/// Bridges the resolved Material [Theme] into the Cupertino theme.
///
/// Used as the app-level `MaterialApp.builder`. Without this, Cupertino
/// surfaces resolve their colors against the platform brightness only — a
/// user-picked dark theme on a light device would keep light Cupertino
/// chrome (large-title nav bars) over dark content.
Widget bridgeCupertinoTheme(BuildContext context, Widget? child) {
  return CupertinoTheme(
    data: CupertinoThemeData(
      brightness: Theme.of(context).brightness,
      primaryColor: Theme.of(context).colorScheme.primary,
      textTheme: CupertinoTheme.of(context).textTheme,
    ),
    child: child!,
  );
}
