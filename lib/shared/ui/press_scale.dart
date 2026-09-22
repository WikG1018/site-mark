import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sitemark/motion.dart';

/// Gives any tappable surface a system-grade press response: the child
/// scales down under the finger with a spring settle on release, so press
/// feedback no longer depends on Material's splash highlight (which iOS
/// renders as `NoSplash`).
///
/// When [haptic] is non-null, it fires once per accepted press (not on
/// release), matching the MiHaptic "transient" touch point language.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.onPressed,
    required this.child,
    this.scaleDown = 0.96,
    this.haptic,
  });

  final VoidCallback? onPressed;
  final Widget child;

  /// Scale while the finger rests down. Cramped surfaces can pass a larger
  /// value (less shrink).
  final double scaleDown;

  /// Optional haptic fired on press start (e.g. [HapticFeedback.selectionClick]).
  final Future<void> Function()? haptic;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.short4,
      reverseDuration: const Duration(milliseconds: 220),
      value: 1,
    );
    _controller
      ..duration = AppMotion.short4
      ..reverseDuration = const Duration(milliseconds: 220);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDown(TapDownDetails details) {
    if (widget.onPressed == null) return;
    _controller
      ..duration = const Duration(milliseconds: 110)
      ..animateTo(widget.scaleDown, curve: Curves.easeOut);
  }

  void _handleUp() {
    _controller
      ..duration = AppMotion.short4
      ..animateTo(1, curve: AppMotion.springScaleSettle);
  }

  void _handleTap() {
    if (widget.onPressed == null) return;
    unawaitedHaptic();
    widget.onPressed!();
  }

  void unawaitedHaptic() {
    final haptic = widget.haptic;
    if (haptic != null) {
      // Fire-and-forget: haptics must never gate the callback.
      haptic();
    }
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onPressed != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: interactive ? _handleDown : null,
      onTapUp: interactive ? (_) => _handleUp() : null,
      onTapCancel: interactive ? _handleUp : null,
      onTap: interactive ? _handleTap : null,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) =>
            Transform.scale(scale: _controller.value, child: child),
        child: widget.child,
      ),
    );
  }
}
