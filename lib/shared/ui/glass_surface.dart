import 'dart:ui';

import 'package:flutter/material.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding,
    this.opacity = .72,
    this.blurSigma = 16,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final double opacity;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final blurEnabled =
        blurSigma > 0 && !MediaQuery.disableAnimationsOf(context);
    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(
          alpha: opacity.clamp(.58, .92).toDouble(),
        ),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .55)),
        borderRadius: borderRadius,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: scheme.onSurface),
        child: IconTheme.merge(
          data: IconThemeData(color: scheme.onSurface),
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      ),
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
