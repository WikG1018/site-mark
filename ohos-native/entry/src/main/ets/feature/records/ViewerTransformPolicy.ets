/** Zoomed-photo pan/zoom physics, mirroring the Android fullscreen viewer
 * (Phase D, spec §3.5): rubber-band past the pan bound, damped release
 * inertia, spring snap-back. Pure logic — the screen supplies gestures. */
export class ViewerTransformPolicy {
  /// Damping applied to offsets beyond the pan bound.
  static readonly RUBBER_BAND: number = 0.25;
  /// Release drift factor applied to the tracked velocity (px/s → px).
  static readonly INERTIA_FACTOR: number = 0.18;
  static readonly DOUBLE_TAP_MIN: number = 1.2;
  static readonly DOUBLE_TAP_MAX: number = 2.5;
  /// Spec fallback when the photo's content rect cannot be measured.
  static readonly DOUBLE_TAP_FALLBACK: number = 2.0;

  /** Rubber-band one axis against its pan bound: legal inside the bound,
   * damped (×[RUBBER_BAND]) outside so the photo resists then springs back. */
  static rubberBand(offset: number, maxOffset: number): number {
    if (!Number.isFinite(offset)) {
      return 0;
    }
    if (maxOffset <= 0) {
      return 0;
    }
    if (offset > maxOffset) {
      return maxOffset + (offset - maxOffset) * ViewerTransformPolicy.RUBBER_BAND;
    }
    if (offset < -maxOffset) {
      return -maxOffset + (offset + maxOffset) * ViewerTransformPolicy.RUBBER_BAND;
    }
    return offset;
  }

  /** Release drift for a tracked velocity in px/s; NaN/non-finite → 0. */
  static inertiaOffset(velocityPxPerSec: number): number {
    if (!Number.isFinite(velocityPxPerSec)) {
      return 0;
    }
    return velocityPxPerSec * ViewerTransformPolicy.INERTIA_FACTOR;
  }

  /** Double-tap zoom target. The content-rect fill cannot be measured
   * without the photo's intrinsic size, so callers pass a measured scale or
   * null for the spec's 2x fallback; either way clamped to [min, max]. */
  static doubleTapTarget(measured: number | null): number {
    const base = measured !== null && Number.isFinite(measured) && measured > 1
      ? measured
      : ViewerTransformPolicy.DOUBLE_TAP_FALLBACK;
    return Math.min(ViewerTransformPolicy.DOUBLE_TAP_MAX,
      Math.max(ViewerTransformPolicy.DOUBLE_TAP_MIN, base));
  }
}
