import { MotionPolicy } from './MotionPolicy';

/** One gesture's press-visual state. Pure data so tests can drive it. */
export class PressGestureState {
  readonly pressed: boolean;
  readonly cancelled: boolean;
  readonly startX: number;
  readonly startY: number;

  constructor(pressed: boolean, cancelled: boolean, startX: number, startY: number) {
    this.pressed = pressed;
    this.cancelled = cancelled;
    this.startX = startX;
    this.startY = startY;
  }

  static idle(): PressGestureState {
    return new PressGestureState(false, false, 0, 0);
  }
}

/** Minimal touch shape (TouchType name + viewport vp) so the policy stays
 * unit-testable without an ArkUI runtime. */
export interface PressGestureEvent {
  type: string;
  x: number;
  y: number;
}

/** Press-scale policy mirroring `lib/shared/ui/press_scale.dart`: driven by
 * raw pointer events (tap recognizers have a ~100ms dead zone — too late for
 * a press visual), slop crossing cancels the press for the rest of the
 * gesture, and reduce-motion keeps the surface completely still (a jump-cut
 * is more startling than the animation; haptics carry the feedback). */
export class PressGesturePolicy {
  static readonly SCALE: number = 0.96;
  static readonly SLOP_VP: number = 8;

  static next(state: PressGestureState, event: PressGestureEvent): PressGestureState {
    if (event.type === 'Down') {
      return new PressGestureState(true, false, event.x, event.y);
    }
    if (event.type === 'Move') {
      if (!state.pressed) {
        return state;
      }
      const dx = event.x - state.startX;
      const dy = event.y - state.startY;
      if (Math.sqrt(dx * dx + dy * dy) > PressGesturePolicy.SLOP_VP) {
        return new PressGestureState(false, true, state.startX, state.startY);
      }
      return state;
    }
    // Up / Cancel end the gesture and re-arm the next one.
    return PressGestureState.idle();
  }

  /** The scale factor for the current state; always 1 under reduce-motion. */
  static scaleOf(state: PressGestureState): number {
    if (MotionPolicy.reduceMotion || !state.pressed) {
      return 1;
    }
    return PressGesturePolicy.SCALE;
  }
}

/** Adapts an ArkUI TouchEvent to the testable [PressGestureEvent] shape. */
export function pressGestureEventOf(event: TouchEvent): PressGestureEvent {
  const touch = event.touches[0];
  return { type: `${event.type}`, x: touch.x, y: touch.y };
}
