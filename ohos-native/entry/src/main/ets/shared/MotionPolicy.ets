import { accessibility } from '@kit.AccessibilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';

export class MotionPolicy {
  static reduceMotion: boolean = false;

  static async refresh(): Promise<void> {
    if (deviceInfo.sdkApiVersion < 23) {
      MotionPolicy.reduceMotion = false;
      return;
    }
    try {
      MotionPolicy.reduceMotion = await accessibility.isAnimationReduceEnabled();
    } catch (_) {
      MotionPolicy.reduceMotion = false;
    }
  }

  static duration(normal: number): number {
    return MotionPolicy.reduceMotion ? 0 : normal;
  }

  static blur(normal: number): number {
    return MotionPolicy.reduceMotion ? 0 : normal;
  }
}
