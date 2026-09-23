import 'package:flutter/material.dart';

import 'package:sitemark/shared/ui/glass_surface.dart';
import 'package:sitemark/shared/ui/press_scale.dart';

/// Floating action affordance in the app's glass chrome vocabulary — the
/// same family as the navigation dock and toast capsule. Used on every
/// platform so "New project" and "Capture" do not flip between a solid
/// Material FAB and a glass pill.
class AdaptiveFloatingButton extends StatelessWidget {
  const AdaptiveFloatingButton({
    super.key,
    required this.onPressed,
    this.tooltip,
    this.icon,
    this.label,
    this.heroTag,
  });

  final VoidCallback? onPressed;

  /// Extended variant is used when [label] is non-null; then [icon] and
  /// [label] render inside a pill. Otherwise [icon] renders in a circle.
  final IconData? icon;
  final String? label;
  final String? tooltip;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final extended = label != null;
    final foreground = Theme.of(context).colorScheme.onSurface;
    final radius = BorderRadius.circular(999);
    // PressScale owns the press/tap gesture (scale-down under the finger,
    // spring settle on release); the ink-free glass pill keeps its hover
    // styling from GlassSurface alone.
    final content = Material(
      color: Colors.transparent,
      child: extended
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) Icon(icon, size: 22, color: foreground),
                  const SizedBox(width: 8),
                  Text(
                    label!,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Icon(icon, size: 24, color: foreground),
            ),
    );
    final glass = GlassSurface(
      borderRadius: radius,
      opacity: GlassChrome.opacity,
      blurSigma: GlassChrome.blurSigma,
      // Match the root dock: one always-on glass layer keeps the FAB in the
      // same material family without a per-list-card blur cost.
      blurOnAndroid: true,
      child: PressScale(
        // No press haptic: the FAB opens a screen — a navigation hop is not
        // a semantic action. Haptics stay with the action itself (e.g. the
        // form's submit tick) so one action reads as exactly one touch.
        onPressed: onPressed,
        child: content,
      ),
    );
    return tooltip == null ? glass : Tooltip(message: tooltip!, child: glass);
  }
}
