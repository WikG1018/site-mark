import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sitemark/motion.dart';

/// Default scale under the finger for interactive surfaces. Cramped
/// surfaces can pass a larger [PressScaleView.scaleDown] (less shrink).
const double kInteractivePressScale = 0.96;

/// Visual press response for any tappable surface: the child scales down
/// under the finger with a spring settle on release, so press feedback no
/// longer depends on Material's splash highlight (which iOS renders as
/// `NoSplash`).
///
/// The response is driven by raw pointer events, not a tap recognizer:
/// `onTapDown` only fires after a tap deadline or an arena sweep, which
/// would delay the visual by ~100 ms. The finger must feel the surface
/// respond on contact. Dragging past the touch slop cancels the press
/// (list-scroll handoff), and the scale springs back on release.
///
/// This widget is purely visual: taps and semantics stay with the
/// recognizer that owns the surface ([InkWell] or [PressScale]). Pass
/// [haptic] to fire a transient touch-point tick when the press is
/// accepted; hosts with their own haptic language leave it null. Under
/// system reduce-motion the scale is suppressed entirely — the haptic
/// carries the press.
class PressScaleView extends StatefulWidget {
  const PressScaleView({
    super.key,
    required this.child,
    this.scaleDown = kInteractivePressScale,
    this.haptic,
    this.enabled = true,
  });

  final Widget child;

  /// Scale while the finger rests down.
  final double scaleDown;

  /// Fired once when a press completes as a tap (the finger lifts within
  /// the touch slop) — the MiHaptic "transient" touch point
  /// (e.g. [HapticFeedback.lightImpact]). Presses that turn into drags
  /// stay silent, matching what the owning recognizer counts as accepted.
  final Future<void> Function()? haptic;

  /// When false the surface ignores pointers and stays at full scale — a
  /// disabled control must not respond to touch.
  final bool enabled;

  @override
  State<PressScaleView> createState() => _PressScaleViewState();
}

class _PressScaleViewState extends State<PressScaleView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int? _pointer;
  Offset? _downPosition;
  double _slop = kTouchSlop;
  bool _pressed = false;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.short4,
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant PressScaleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _pointer = null;
      _downPosition = null;
      _setPressed(false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDown(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null) return;
    _pointer = event.pointer;
    _downPosition = event.position;
    _slop =
        event.kind == PointerDeviceKind.mouse ||
            event.kind == PointerDeviceKind.trackpad
        ? kPrecisePointerHitSlop
        : kTouchSlop;
    _cancelled = false;
    _setPressed(true);
  }

  void _handleMove(PointerMoveEvent event) {
    if (_pointer != event.pointer || _cancelled) return;
    final down = _downPosition;
    if (down == null) return;
    if (!_withinSlop(event.position - down)) {
      // Past the slop the gesture belongs to a drag; the press ends even if
      // the finger wanders back, matching the tap recognizer.
      _cancelled = true;
      _setPressed(false);
    }
  }

  void _handleUp(PointerUpEvent event) {
    if (_pointer != event.pointer) return;
    final accepted = _pressed;
    _pointer = null;
    _downPosition = null;
    _cancelled = false;
    _setPressed(false);
    if (!accepted) return;
    final haptic = widget.haptic;
    if (haptic != null) {
      // Fire-and-forget: haptics must never gate the response.
      haptic();
    }
  }

  void _handleCancel(PointerCancelEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    _downPosition = null;
    _cancelled = false;
    _setPressed(false);
  }

  bool _withinSlop(Offset delta) =>
      math.max(delta.dx.abs(), delta.dy.abs()) <= _slop;

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    _pressed = pressed;
    _animate();
  }

  void _animate() {
    // Reduced motion: the surface holds still — a jump-cut scale flickers
    // worse than the smooth one it replaces. The haptic carries the press.
    if (MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    if (_pressed) {
      // Quick ease-down reads as "the surface gave" under the finger;
      // the life goes into the release.
      _controller
        ..duration = const Duration(milliseconds: 110)
        ..animateTo(widget.scaleDown, curve: Curves.easeOut);
    } else {
      _controller
        ..duration = AppMotion.short4
        ..animateTo(1, curve: AppMotion.springScaleSettle);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handleDown,
      onPointerMove: _handleMove,
      onPointerUp: _handleUp,
      onPointerCancel: _handleCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) =>
            Transform.scale(scale: _controller.value, child: child),
        child: widget.child,
      ),
    );
  }
}

/// Self-gesturing [PressScaleView]: wraps a plain child in both the press
/// response and a tap recognizer running [onPressed].
///
/// When [haptic] is non-null, it fires once per accepted press (the finger
/// lifts within the touch slop), matching the MiHaptic "transient" touch
/// point language. A null [onPressed] renders a dead surface: no scale, no
/// haptic, no tap.
class PressScale extends StatelessWidget {
  const PressScale({
    super.key,
    required this.onPressed,
    required this.child,
    this.scaleDown = kInteractivePressScale,
    this.haptic,
  });

  final VoidCallback? onPressed;
  final Widget child;

  /// Scale while the finger rests down; see [PressScaleView.scaleDown].
  final double scaleDown;

  /// Optional haptic fired on press start (e.g. [HapticFeedback.lightImpact]).
  final Future<void> Function()? haptic;

  @override
  Widget build(BuildContext context) {
    final interactive = onPressed != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: interactive ? onPressed : null,
      child: PressScaleView(
        scaleDown: scaleDown,
        haptic: interactive ? haptic : null,
        enabled: interactive,
        child: child,
      ),
    );
  }
}
