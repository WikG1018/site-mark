import 'dart:ui';

import 'package:flutter/material.dart';

/// A translucent surface that drops backdrop blur when reduced motion is on.
///
/// The reduced-motion fallback keeps the same colors and border but avoids the
/// live blur layer, so callers should not rely on blur for content contrast.
///
/// Optional top highlight, inset border and extremely subtle noise increase
/// perceived glass thickness without a second live blur pass.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding,
    this.opacity = .72,
    this.blurSigma = 16,
    this.enableNoise = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final double opacity;
  final double blurSigma;

  /// When true (default), a very low-opacity noise overlay is applied.
  /// Set to false to skip the noise layer entirely.
  final bool enableNoise;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blurEnabled =
        blurSigma > 0 && !MediaQuery.disableAnimationsOf(context);
    final noiseEnabled =
        enableNoise && !MediaQuery.disableAnimationsOf(context);

    final highlightAlpha = isDark ? 0.09 : 0.14;
    final insetAlpha = isDark ? 0.10 : 0.12;

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(
          alpha: opacity.clamp(.58, .92).toDouble(),
        ),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .55)),
        borderRadius: borderRadius,
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(
            color: scheme.onSurface.withValues(alpha: insetAlpha),
            width: 1,
          ),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: scheme.onSurface),
          child: IconTheme.merge(
            data: IconThemeData(color: scheme.onSurface),
            child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
          ),
        ),
      ),
    );

    if (noiseEnabled) {
      content = Stack(
        fit: StackFit.passthrough,
        children: [
          content,
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
        ],
      );
    }

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
