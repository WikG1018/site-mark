import 'package:flutter/material.dart';

/// The app's shape language, as a six-step radius scale.
///
/// Every rounded corner in the app draws from this scale — a surface's size
/// and role pick the step, never an ad-hoc number. Six steps keep the system
/// legible: any two neighbouring surfaces differ by exactly one step of
/// visual weight (a 2px halo), so the eye reads one shape family rather
/// than a scatter of similar-but-different corners.
abstract final class AppRadius {
  /// Small inner shapes: list thumbnails, chips, progress tracks.
  static const Radius xs = Radius.circular(8);

  /// Media corners and small surfaces: previews, banners, menu rows.
  static const Radius sm = Radius.circular(12);

  /// Interactive controls: inputs, buttons, segmented controls.
  static const Radius md = Radius.circular(16);

  /// Content containers: cards, settings groups, panel heads.
  static const Radius lg = Radius.circular(20);

  /// Floating chrome capsules: dock, batch bar, toast, FAB.
  static const Radius xl = Radius.circular(24);

  /// Fully rounded pills and circular surfaces.
  static const Radius pill = Radius.circular(999);
}

/// The app's floating-depth vocabulary.
///
/// Central depth roles rather than per-page shadow copies. Ordinary chrome
/// keeps its established soft drop; navigation and its clear lens have
/// separate ambient/contact edges appropriate to their nested geometry.
abstract final class AppShadow {
  /// Wide ambient lift and a quiet contact edge for the navigation pill.
  static List<BoxShadow> navigation(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return [
      BoxShadow(
        color: theme.colorScheme.shadow.withValues(alpha: dark ? .24 : .09),
        blurRadius: 20,
        offset: const Offset(0, 6),
      ),
      BoxShadow(
        color: theme.colorScheme.shadow.withValues(alpha: dark ? .12 : .04),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  /// The transparent lens needs a small refraction edge, not card elevation.
  static List<BoxShadow> glassLens(BuildContext context) => [
    BoxShadow(
      color: Colors.black.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? .16 : .075,
      ),
      blurRadius: 5,
      offset: const Offset(0, 1),
    ),
  ];

  /// Soft drop shadow for floating chrome.
  static List<BoxShadow> chrome(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return [
      BoxShadow(
        color: theme.colorScheme.shadow.withValues(alpha: isDark ? .14 : .08),
        blurRadius: isDark ? 14 : 12,
        offset: const Offset(0, 3),
      ),
    ];
  }
}

abstract final class AppDock {
  static const double height = 64;
  static const double maxWidth = 360;
  static const double outerInset = 4;
  static const double bottomInset = 4;
  static const double contentInset = 5;
  static const double lensInset = 2;
  static const double iconSize = 22;
  static const double labelSize = 12;
  static const BorderRadius radius = BorderRadius.all(AppRadius.pill);
}
