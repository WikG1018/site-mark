import { vibrator } from '@kit.SensorServiceKit';

const SELECTION_CLICK_MS: number = 16;
const MEDIUM_IMPACT_MS: number = 32;

/** Lightweight haptic feedback, mirroring the Android list/card feedback
 *  (selection click on every toggle, medium impact when selection mode
 *  starts). Requires ohos.permission.VIBRATE. All failures are swallowed —
 *  haptics are decorative and must never surface errors or block the action.
 */
export class Haptics {
  /** Short tick for record-selection toggles and light confirmations. */
  static selectionClick(): void {
    Haptics.vibrate(SELECTION_CLICK_MS);
  }

  /** Slightly stronger pulse for entering selection mode. */
  static mediumImpact(): void {
    Haptics.vibrate(MEDIUM_IMPACT_MS);
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
