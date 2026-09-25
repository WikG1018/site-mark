import { curves } from '@kit.ArkUI';

/** Structural stand-in for the ArkUI ICurve handle (interpolate-only, the
 * shape the animation APIs consume; the kit does not export the type). */
interface MotionCurve {
  interpolate(fraction: number): number;
}

/** Motion tokens mirroring `lib/motion.dart` AppMotion (decision D-024).
 * Business code must not hard-code durations or curves — take them from
 * here so the three platforms animate as one family. */
export class MotionTokens {
  /** Icon/opacity micro-interactions and popup exit. */
  static readonly DURATION_SHORT4: number = 180;
  /** Route and panel transitions (pageTransition / medium2). */
  static readonly DURATION_MEDIUM2: number = 260;
  /** Scale animations and list entrance. */
  static readonly DURATION_MEDIUM4: number = 320;
  /** Inertia settle and large travel. */
  static readonly DURATION_LONG2: number = 500;

  /** Dismiss snap-back / chrome slide / dialog enter. ArkUI translation of
   * AppMotion.springSnap (mass .5 / stiffness 100 / damping ratio 1); the
   * dampingFraction IS the Flutter damping ratio, the response value is the
   * platform translation (needs a device handfeel pass). */
  static readonly SPRING_SNAP_RESPONSE: number = 0.30;
  static readonly SPRING_SNAP_DAMPING: number = 1.0;

  /** Press release and scale landing. AppMotion.springSettle (ratio .92). */
  static readonly SPRING_SETTLE_RESPONSE: number = 0.38;
  static readonly SPRING_SETTLE_DAMPING: number = 0.92;

  /** Toast/dock rise and list entrance. AppMotion.springRise (stiffness 140,
   * ratio .85) — the most life. */
  static readonly SPRING_RISE_RESPONSE: number = 0.28;
  static readonly SPRING_RISE_DAMPING: number = 0.85;

  static springSnap(): MotionCurve {
    return curves.springMotion(
      MotionTokens.SPRING_SNAP_RESPONSE,
      MotionTokens.SPRING_SNAP_DAMPING,
    );
  }

  static springSettle(): MotionCurve {
    return curves.springMotion(
      MotionTokens.SPRING_SETTLE_RESPONSE,
      MotionTokens.SPRING_SETTLE_DAMPING,
    );
  }

  static springRise(): MotionCurve {
    return curves.springMotion(
      MotionTokens.SPRING_RISE_RESPONSE,
      MotionTokens.SPRING_RISE_DAMPING,
    );
  }

  /** Cubic control points — exact values from AppMotion. */
  static readonly CUBIC_EMPHASIZED: number[] = [0.2, 0.0, 0.0, 1.0];
  static readonly CUBIC_EMPHASIZED_DECELERATE: number[] = [0.05, 0.7, 0.1, 1.0];
  static readonly CUBIC_EMPHASIZED_ACCELERATE: number[] = [0.3, 0.0, 0.8, 0.15];
  static readonly CUBIC_STANDARD: number[] = [0.2, 0.0, 0.0, 1.0];
  static readonly CUBIC_STANDARD_ACCELERATE: number[] = [0.3, 0.0, 1.0, 1.0];

  static emphasized(): MotionCurve {
    const p = MotionTokens.CUBIC_EMPHASIZED;
    return curves.cubicBezierCurve(p[0], p[1], p[2], p[3]);
  }

  static emphasizedDecelerate(): MotionCurve {
    const p = MotionTokens.CUBIC_EMPHASIZED_DECELERATE;
    return curves.cubicBezierCurve(p[0], p[1], p[2], p[3]);
  }

  static emphasizedAccelerate(): MotionCurve {
    const p = MotionTokens.CUBIC_EMPHASIZED_ACCELERATE;
    return curves.cubicBezierCurve(p[0], p[1], p[2], p[3]);
  }

  static standard(): MotionCurve {
    const p = MotionTokens.CUBIC_STANDARD;
    return curves.cubicBezierCurve(p[0], p[1], p[2], p[3]);
  }

  static standardAccelerate(): MotionCurve {
    const p = MotionTokens.CUBIC_STANDARD_ACCELERATE;
    return curves.cubicBezierCurve(p[0], p[1], p[2], p[3]);
  }
}
