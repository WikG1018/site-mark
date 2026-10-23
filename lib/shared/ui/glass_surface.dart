import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sitemark/design_tokens.dart';

/// Shared material presets. Ordinary chrome retains its standard recipe;
/// navigation has a neutral body and a colorless moving lens, never an accent
/// fill copied into individual pages. Only the outer body uses live blur.
class GlassChrome {
  const GlassChrome._();

  /// Surface fill. Low enough that backdrop color still reads through the
  /// blur; high enough that on-surface icons and labels stay legible.
  static const double opacity = .58;

  /// Backdrop blur. Strong enough that the low fill still frosts the
  /// background into a single wash.
  static const double blurSigma = 20;

  static const double navigationLightOpacity = .76;
  static const double navigationDarkOpacity = .84;
}

/// Navigation uses a neutral polished body; its moving lens is colorless.
/// Both are central recipes. Other glass surfaces retain their current look.
enum GlassSurfaceStyle { standard, navigation, lens }

/// A translucent surface that drops backdrop blur when reduced motion is on.
///
/// The reduced-motion fallback keeps the same colors and border but avoids the
/// live blur layer, so callers should not rely on blur for content contrast.
///
/// Optional top highlight, inset border and extremely subtle overlay tint
/// increase perceived glass thickness without a second live blur pass.
///
/// Defaults retain the standard [GlassChrome] recipe. Navigation and lens
/// styles are opt-in centralized presets; they do not change cards, batch
/// bars, FABs or toasts. Reduced motion/high contrast use opaque neutral fills.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(AppRadius.lg),
    this.padding,
    this.opacity = GlassChrome.opacity,
    this.blurSigma = GlassChrome.blurSigma,
    this.blurOnAndroid = false,
    this.enableOverlay = true,
    this.boxShadow,
    this.style = GlassSurfaceStyle.standard,
    this.lightDirection = 0,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final double opacity;
  final double blurSigma;
  final GlassSurfaceStyle style;

  /// Subtle specular shift while a lens travels, in the range -1..1.
  final double lightDirection;

  /// Keeps the live backdrop blur on Android, where [GlassSurface] otherwise
  /// falls back to the tinted surface. Reserve this for single, always-on
  /// chrome like the navigation dock: one small blur layer per frame is
  /// affordable, while one per list card is what drops frames.
  final bool blurOnAndroid;

  /// When true (default), a very low-opacity flat tint is applied with
  /// [BlendMode.overlay] **under** the child content (chrome only).
  /// This is not grain/noise texture. Set to false to skip the overlay layer.
  final bool enableOverlay;

  /// Drop shadow for surfaces that float over content (see
  /// [AppShadow.chrome]). It paints outside the clip; content that sits in a
  /// card stays flat — only hovering chrome carries depth.
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final polished = style != GlassSurfaceStyle.standard;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final highContrast = MediaQuery.highContrastOf(context);
    // Android BackdropFilter is a saveLayer per widget per frame. List cards
    // and page transitions drop frames; iOS blur stays compositor-cheap.
    // Single chrome surfaces opt back in via [blurOnAndroid].
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final blurEnabled =
        blurSigma > 0 &&
        !reduceMotion &&
        style != GlassSurfaceStyle.lens &&
        !(polished && highContrast) &&
        (!isAndroid || blurOnAndroid);
    final solidPolish = polished && (reduceMotion || highContrast);
    final effectiveOpacity = switch (style) {
      GlassSurfaceStyle.standard =>
        blurEnabled
            ? opacity.clamp(0.58, 0.92)
            : (opacity + 0.10).clamp(0.58, 0.94),
      GlassSurfaceStyle.navigation =>
        solidPolish
            ? 1.0
            : isDark
            ? GlassChrome.navigationDarkOpacity
            : GlassChrome.navigationLightOpacity,
      GlassSurfaceStyle.lens =>
        solidPolish
            ? 1.0
            : isDark
            ? .16
            : .40,
    };
    final fillColor = switch (style) {
      GlassSurfaceStyle.standard => scheme.surface,
      GlassSurfaceStyle.navigation =>
        isDark ? const Color(0xff202326) : const Color(0xfff8fafb),
      GlassSurfaceStyle.lens =>
        !isDark
            ? Colors.white
            : solidPolish
            ? const Color(0xff3b4044)
            : const Color(0xff9ba4aa),
    };
    // BlendMode.overlay can force an extra offscreen pass on Android's
    // compositor. Keep it only for single chrome surfaces that already pay
    // for live blur (the navigation dock); list cards and pages stay flat.
    final overlayEnabled =
        enableOverlay &&
        !polished &&
        !reduceMotion &&
        (!isAndroid || blurOnAndroid);

    final highlightAlpha = isDark ? 0.09 : 0.14;
    final insetAlpha = isDark ? 0.10 : 0.12;

    // Outer fill + border. Highlight, optional overlay tint, and content share a
    // Stack so tint paints under text/icons (not over them). BoxDecoration
    // ignores [color] when [gradient] is set, so fill and highlight stay nested.
    final layers = <Widget>[
      if (polished)
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              key: Key('glass-${style.name}-sheen'),
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: LinearGradient(
                  begin: Alignment(
                    -1 + lightDirection.clamp(-1.0, 1.0) * .6,
                    -1,
                  ),
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(
                      alpha: isDark
                          ? style == GlassSurfaceStyle.lens
                                ? .035
                                : .06
                          : .48,
                    ),
                    Colors.white.withValues(alpha: 0),
                    Colors.black.withValues(alpha: isDark ? .04 : .025),
                  ],
                  stops: const [0, .48, 1],
                ),
              ),
            ),
          ),
        )
      else
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
      if (polished)
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _PolishedGlassRim(
                borderRadius: borderRadius,
                lightDirection: lightDirection,
                colors: highContrast
                    ? [
                        scheme.onSurface.withValues(alpha: .28),
                        scheme.onSurface.withValues(alpha: .28),
                      ]
                    : [
                        Colors.white.withValues(alpha: isDark ? .40 : .95),
                        Colors.white.withValues(alpha: isDark ? .08 : .24),
                        Colors.black.withValues(alpha: isDark ? .18 : .09),
                      ],
              ),
            ),
          ),
        ),
    ];

    Widget content = DecoratedBox(
      key: polished ? Key('glass-${style.name}-fill') : null,
      decoration: BoxDecoration(
        color: fillColor.withValues(alpha: effectiveOpacity.toDouble()),
        border: polished
            ? null
            : Border.all(color: scheme.outlineVariant.withValues(alpha: .55)),
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
    final clipped = RepaintBoundary(
      child: ClipRRect(borderRadius: borderRadius, child: content),
    );
    if (boxShadow == null) return clipped;
    // The clip would cut a child-bound shadow, so depth wraps the clipped
    // glass from outside.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: boxShadow,
      ),
      child: clipped,
    );
  }
}

/// A lighting edge painted directly, without a shader mask/saveLayer.
class _PolishedGlassRim extends CustomPainter {
  const _PolishedGlassRim({
    required this.borderRadius,
    required this.colors,
    required this.lightDirection,
  });

  final BorderRadius borderRadius;
  final List<Color> colors;
  final double lightDirection;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment(-1 + lightDirection.clamp(-1.0, 1.0) * .6, -1),
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(bounds);
    canvas.drawRRect(borderRadius.toRRect(bounds).deflate(.5), paint);
  }

  @override
  bool shouldRepaint(_PolishedGlassRim oldDelegate) =>
      borderRadius != oldDelegate.borderRadius ||
      lightDirection != oldDelegate.lightDirection ||
      !listEquals(colors, oldDelegate.colors);
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(AppRadius.lg),
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
