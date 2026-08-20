import { accessibility } from '@kit.AccessibilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';

export type ReduceMotionQuery = () => Promise<boolean>;

export class ReduceMotionQueryPolicy {
  static async read(sdkApiVersion: number, query: ReduceMotionQuery): Promise<boolean> {
    if (sdkApiVersion < 23) {
      return false;
    }
    try {
      return await query();
    } catch (_) {
      return false;
    }
  }
}

export class MotionPolicy {
  static reduceMotion: boolean = false;

  static async refresh(): Promise<void> {
    if (deviceInfo.sdkApiVersion < 23) {
      MotionPolicy.reduceMotion = false;
      return;
    }
    await MotionPolicy.refreshFor(deviceInfo.sdkApiVersion, (): Promise<boolean> =>
      accessibility.isAnimationReduceEnabled());
  }

  static async refreshFor(sdkApiVersion: number, query: ReduceMotionQuery): Promise<void> {
    MotionPolicy.reduceMotion = await ReduceMotionQueryPolicy.read(sdkApiVersion, query);
  }

  static duration(normal: number): number {
    return MotionPolicy.reduceMotion ? 0 : normal;
  }

  static blur(normal: number): number {
    return MotionPolicy.reduceMotion ? 0 : normal;
  }
}
