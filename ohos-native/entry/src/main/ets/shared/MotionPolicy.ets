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

  static async read(): Promise<boolean> {
    return await MotionPolicy.readFor(deviceInfo.sdkApiVersion, (): Promise<boolean> =>
      accessibility.isAnimationReduceEnabled());
  }

  static async readFor(sdkApiVersion: number, query: ReduceMotionQuery): Promise<boolean> {
    return await ReduceMotionQueryPolicy.read(sdkApiVersion, query);
  }

  static commit(reduceMotion: boolean): void {
    MotionPolicy.reduceMotion = reduceMotion;
  }

  static async refresh(): Promise<void> {
    MotionPolicy.commit(await MotionPolicy.read());
  }

  static async refreshFor(sdkApiVersion: number, query: ReduceMotionQuery): Promise<void> {
    MotionPolicy.commit(await MotionPolicy.readFor(sdkApiVersion, query));
  }

  static duration(normal: number): number {
    return MotionPolicy.reduceMotion ? 0 : normal;
  }

  static blur(normal: number): number {
    return MotionPolicy.reduceMotion ? 0 : normal;
  }
}
