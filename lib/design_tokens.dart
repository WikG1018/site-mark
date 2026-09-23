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
/// One shadow recipe for everything that hovers over content. Per-surface
/// shadow tuning reads as different materials under the same glass; a single
/// soft drop keeps every capsule in one depth plane (and keeps dark mode
/// honest — its slightly stronger, wider shadow is what sells elevation on
/// a dark backdrop).
abstract final class AppShadow {
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
