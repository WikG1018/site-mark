import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A [Curve] sampled from a spring's normalized displacement.
///
/// Springs deliver the "life" of motion (a small overshoot before settling)
/// that a plain cubic can never express. Endpoints are snapped exactly to
/// 0/1 — whatever residual the one-second sample carries is divided out —
/// so these curves are safe for value-space drivers whose extremes must be
/// exact (visibility, scale targets, dismiss snap-back).
class SpringCurve extends Curve {
  const SpringCurve(this.description);

  final SpringDescription description;

  @override
  double transformInternal(double t) {
    final simulation = SpringSimulation(description, 0, 1, 0);
    final value = simulation.x(t);
    final end = simulation.x(1);
    return end == 0 ? value : value / end;
  }

  @override
  String toString() => 'SpringCurve($description)';
}

abstract final class AppMotion {
  static const Duration rootSwitch = Duration(milliseconds: 220);
  static const Duration pageTransition = Duration(milliseconds: 260);
  static const Duration short4 = Duration(milliseconds: 180);
  static const Duration scrollChrome = Duration(milliseconds: 220);

  /// Extra off-viewport pixels kept laid out for photo-heavy scrollables.
  ///
  /// Flutter's default 250 px is only ~2 card heights; fast flings dispose
  /// thumbnail rows before they re-enter, which flashes a placeholder.
  static const ScrollCacheExtent photoListCacheExtent =
      ScrollCacheExtent.pixels(500);
  static const Duration medium2 = pageTransition;
  static const Duration medium4 = Duration(milliseconds: 320);
  static const Duration long2 = Duration(milliseconds: 500);

  static const Cubic emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Cubic emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);
  static const Cubic emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);
  static const Cubic standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Cubic standardDecelerate = Cubic(0.0, 0.0, 0.0, 1.0);
  static const Cubic standardAccelerate = Cubic(0.3, 0.0, 1.0, 1.0);

  // Springs (engineering parameters: Flutter's iOS family default —
  // mass .5 / stiffness 100 — at three damping ratios; the lightly
  // underdamped band carries the "life" overshoot without reading as
  // wobble). `SpringDescription.withDampingRatio` is not const, so the
  // derived curves are `static final`.
  /// Near-critical spring for dismiss snap-back and chrome slides.
  static final SpringDescription springSnap =
      SpringDescription.withDampingRatio(mass: 0.5, stiffness: 100, ratio: 1);

  /// Lightly underdamped spring for scale/settle motion.
  static final SpringDescription springSettle =
      SpringDescription.withDampingRatio(mass: 0.5, stiffness: 100, ratio: .92);

  /// Taut underdamped spring for pill/panel rises.
  static final SpringDescription springRise =
      SpringDescription.withDampingRatio(mass: 0.5, stiffness: 140, ratio: .85);

  /// Snap-back motion (dismiss return, chrome hide/show): ends exactly at
  /// the target with a whisper of settle.
  static final SpringCurve springSnapBack = SpringCurve(springSnap);

  /// Scale settle (press release, zoom settle, toast entrance): visible
  /// but restrained overshoot past the target.
  static final SpringCurve springScaleSettle = SpringCurve(springSettle);

  /// Pill/panel rise (toast, dock, floating chrome): the most life.
  static final SpringCurve springSlideRise = SpringCurve(springRise);

  /// Returns [duration] unless the user has enabled system reduce-motion,
  /// in which case animations collapse to zero for accessibility.
  static Duration durationOf(BuildContext context, Duration duration) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
  }

  /// Popup motion for [showDialog]-style routes: the material fade+scale
  /// transition carried by the snap-back spring, so a dialog arrives in the
  /// same motion language as pages instead of a stock 150 ms fade. Exits
  /// accelerate out decisively; reduce-motion collapses to none.
  static AnimationStyle dialogStyleOf(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return AnimationStyle.noAnimation;
    }
    return AnimationStyle(
      curve: springSnapBack,
      duration: const Duration(milliseconds: 220),
      reverseCurve: standardAccelerate,
      reverseDuration: short4,
    );
  }

  /// Bottom-sheet counterpart of [dialogStyleOf]: a sheet is a longer
  /// travel, so it takes the page duration with the same snap-back curve.
  static AnimationStyle sheetStyleOf(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return AnimationStyle.noAnimation;
    }
    return AnimationStyle(
      curve: springSnapBack,
      duration: medium2,
      reverseCurve: standardAccelerate,
      reverseDuration: short4,
    );
  }
}
