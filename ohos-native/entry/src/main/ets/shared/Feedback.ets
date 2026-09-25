import { vibrator } from '@kit.SensorServiceKit';

/** Lightweight haptic feedback mirroring the Android tiers (MiHaptic intent
 * mapped onto time-type vibrations ★): selection click / light impact on
 * every toggle and successful submit, medium when selection mode starts,
 * heavy on destructive batch confirmation. One semantic action = at most one
 * haptic; navigation surfaces and invalid submits stay silent. Requires
 * ohos.permission.VIBRATE. All failures are swallowed — haptics are
 * decorative and must never surface errors or block the action. */
export class Haptics {
  static readonly SELECTION_CLICK_MS: number = 16;
  static readonly LIGHT_IMPACT_MS: number = 16;
  static readonly MEDIUM_IMPACT_MS: number = 32;
  static readonly HEAVY_IMPACT_MS: number = 48;

  /** Short tick for record-selection toggles, switches and segments. */
  static selectionClick(): void {
    Haptics.vibrate(Haptics.SELECTION_CLICK_MS);
  }

  /** Light pulse for successful form submits and setting changes. */
  static lightImpact(): void {
    Haptics.vibrate(Haptics.LIGHT_IMPACT_MS);
  }

  /** Slightly stronger pulse for entering selection mode. */
  static mediumImpact(): void {
    Haptics.vibrate(Haptics.MEDIUM_IMPACT_MS);
  }

  /** Strong pulse for destructive batch confirmation going through. */
  static heavyImpact(): void {
    Haptics.vibrate(Haptics.HEAVY_IMPACT_MS);
  }

  private static vibrate(durationMs: number): void {
    try {
      vibrator.startVibration(
        { type: 'time', duration: durationMs },
        { usage: 'touch' },
      ).catch((): void => {
      });
    } catch (_) {
    }
  }
}

/** Auto-clear scheduler for transient status messages (the SnackBar
 *  equivalent of the Android version). Each screen owns one instance;
 *  success/info messages clear themselves after AUTO_CLEAR_MS while error
 *  messages stay until replaced or the screen goes away.
 */
/** Injectable timer shims so host tests can drive the clock deterministically;
 *  production falls back to the global timer functions. */
export type TimerScheduler = (callback: () => void, delayMs: number) => number;
export type TimerCanceller = (timer: number) => void;

const defaultTimerScheduler: TimerScheduler =
  (callback: () => void, delayMs: number): number => setTimeout(callback, delayMs);
const defaultTimerCanceller: TimerCanceller = (timer: number): void => {
  clearTimeout(timer);
};

export class ScreenMessageClock {
  static readonly AUTO_CLEAR_MS: number = 4000;

  private timer: number = -1;
  private readonly scheduleFn: TimerScheduler;
  private readonly cancelFn: TimerCanceller;

  constructor(scheduleFn?: TimerScheduler, cancelFn?: TimerCanceller) {
    this.scheduleFn = scheduleFn !== undefined ? scheduleFn : defaultTimerScheduler;
    this.cancelFn = cancelFn !== undefined ? cancelFn : defaultTimerCanceller;
  }

  /** Cancels any pending auto-clear. Call before setting a replacement and
   *  from the screen's aboutToDisappear. */
  reset(): void {
    if (this.timer >= 0) {
      this.cancelFn(this.timer);
      this.timer = -1;
    }
  }

  /** Schedules `clear` after AUTO_CLEAR_MS; errors pass delayMs = 0 and stay
   *  until replaced or disposed. */
  schedule(clear: () => void, delayMs: number): void {
    this.reset();
    if (delayMs <= 0) {
      return;
    }
    this.timer = this.scheduleFn((): void => {
      this.timer = -1;
      clear();
    }, delayMs);
  }

  /** Transient success/info message: shows `text` immediately and clears it
   *  after AUTO_CLEAR_MS. Error messages should reset() and set the text
   *  instead so they stay until replaced or the screen goes away. */
  show(setMessage: (text: string) => void, text: string): void {
    setMessage(text);
    this.schedule((): void => {
      setMessage('');
    }, ScreenMessageClock.AUTO_CLEAR_MS);
  }
}
