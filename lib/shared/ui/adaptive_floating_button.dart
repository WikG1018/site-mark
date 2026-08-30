import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:sitemark/shared/ui/glass_surface.dart';

/// Floating action affordance following each platform's shape: a Material
/// [FloatingActionButton] (circular, or extended when [label] is given)
/// everywhere else; a Liquid Glass capsule — the iOS 27 floating accessory —
/// on iOS.
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
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      // The wrapper carries the caller's key; adding it to the inner FAB
      // too would make finders ambiguous.
      final button = extended
          ? FloatingActionButton.extended(
              heroTag: heroTag,
              onPressed: onPressed,
              icon: icon == null ? null : Icon(icon),
              label: Text(label!),
            )
          : FloatingActionButton(
              heroTag: heroTag,
              onPressed: onPressed,
              child: icon == null ? null : Icon(icon),
            );
      return tooltip == null
          ? button
          : Tooltip(message: tooltip!, child: button);
    }
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
      child: content,
    );
    return tooltip == null ? glass : Tooltip(message: tooltip!, child: glass);
  }
}
