import 'package:flutter/material.dart';

import 'package:sitemark/shared/ui/glass_surface.dart';

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
    final content = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        child: extended
            ? Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
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
      ),
    );
    final glass = GlassSurface(
      borderRadius: radius,
      blurSigma: 22,
      // Match the root dock: one always-on glass layer keeps the FAB in the
      // same material family without a per-list-card blur cost.
      blurOnAndroid: true,
      child: content,
    );
    return tooltip == null ? glass : Tooltip(message: tooltip!, child: glass);
  }
}
