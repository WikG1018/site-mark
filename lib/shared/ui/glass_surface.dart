import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A translucent surface that drops backdrop blur when reduced motion is on.
///
/// The reduced-motion fallback keeps the same colors and border but avoids the
/// live blur layer, so callers should not rely on blur for content contrast.
///
/// Optional top highlight, inset border and extremely subtle overlay tint
/// increase perceived glass thickness without a second live blur pass.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding,
    this.opacity = .72,
    this.blurSigma = 16,
    this.blurOnAndroid = false,
    this.enableOverlay = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final double opacity;
  final double blurSigma;

  /// Keeps the live backdrop blur on Android, where [GlassSurface] otherwise
  /// falls back to the tinted surface. Reserve this for single, always-on
  /// chrome like the navigation dock: one small blur layer per frame is
  /// affordable, while one per list card is what drops frames.
  final bool blurOnAndroid;

  /// When true (default), a very low-opacity flat tint is applied with
  /// [BlendMode.overlay] **under** the child content (chrome only).
  /// This is not grain/noise texture. Set to false to skip the overlay layer.
  final bool enableOverlay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Android BackdropFilter is a saveLayer per widget per frame. List cards
    // and page transitions drop frames; iOS blur stays compositor-cheap.
    // Single chrome surfaces opt back in via [blurOnAndroid].
    final blurEnabled =
        blurSigma > 0 &&
        !MediaQuery.disableAnimationsOf(context) &&
        (defaultTargetPlatform != TargetPlatform.android || blurOnAndroid);
    // Always clamp so callers cannot push opacity outside a readable glass band.
    final effectiveOpacity = blurEnabled
        ? opacity.clamp(0.58, 0.92)
        : (opacity + 0.10).clamp(0.58, 0.94);
    final overlayEnabled =
        enableOverlay && !MediaQuery.disableAnimationsOf(context);

    final highlightAlpha = isDark ? 0.09 : 0.14;
    final insetAlpha = isDark ? 0.10 : 0.12;

    // Outer fill + border. Highlight, optional overlay tint, and content share a
    // Stack so tint paints under text/icons (not over them). BoxDecoration
    // ignores [color] when [gradient] is set, so fill and highlight stay nested.
    final layers = <Widget>[
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: scheme.onSurface.withValues(alpha: insetAlpha),
              width: 1,
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: highlightAlpha),
                Colors.white.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.38],
            ),
          ),
        ),
      ),
      if (overlayEnabled)
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                color: scheme.onSurface.withValues(alpha: 0.035),
                backgroundBlendMode: BlendMode.overlay,
              ),
            ),
          ),
        ),
      DefaultTextStyle.merge(
        style: TextStyle(color: scheme.onSurface),
        child: IconTheme.merge(
          data: IconThemeData(color: scheme.onSurface),
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      ),
    ];

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: effectiveOpacity.toDouble()),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .55)),
        borderRadius: borderRadius,
      ),
      child: Stack(fit: StackFit.passthrough, children: layers),
    );

    if (blurEnabled) {
      content = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: content,
      );
    }
    return RepaintBoundary(
      child: ClipRRect(borderRadius: borderRadius, child: content),
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => GlassSurface(
    borderRadius: borderRadius,
    blurSigma: 0,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}
