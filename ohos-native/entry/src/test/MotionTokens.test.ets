import { describe, expect, it } from '@ohos/hypium';
import { MotionTokens } from '../main/ets/shared/MotionTokens';

export default function motionTokensTest(): void {
  describe('MotionTokens', () => {
    it('mirrors the AppMotion duration set', 0, () => {
      expect(MotionTokens.DURATION_SHORT4).assertEqual(180);
      expect(MotionTokens.DURATION_MEDIUM2).assertEqual(260);
      expect(MotionTokens.DURATION_MEDIUM4).assertEqual(320);
      expect(MotionTokens.DURATION_LONG2).assertEqual(500);
    });

    it('keeps the Flutter spring damping ratios', 0, () => {
      expect(MotionTokens.SPRING_SNAP_DAMPING).assertEqual(1.0);
      expect(MotionTokens.SPRING_SETTLE_DAMPING).assertEqual(0.92);
      expect(MotionTokens.SPRING_RISE_DAMPING).assertEqual(0.85);
    });

    it('orders the springs by stiffness like AppMotion', 0, () => {
      // springRise is the stiffest (140) so it must have the smallest
      // response; springSettle (ratio .92) settles slowest.
      expect(MotionTokens.SPRING_RISE_RESPONSE < MotionTokens.SPRING_SNAP_RESPONSE).assertTrue();
      expect(MotionTokens.SPRING_SNAP_RESPONSE < MotionTokens.SPRING_SETTLE_RESPONSE).assertTrue();
    });

    it('builds the spring and cubic curves', 0, () => {
      expect(MotionTokens.springSnap() !== undefined).assertTrue();
      expect(MotionTokens.springSettle() !== undefined).assertTrue();
      expect(MotionTokens.springRise() !== undefined).assertTrue();
      expect(MotionTokens.emphasized() !== undefined).assertTrue();
      expect(MotionTokens.emphasizedDecelerate() !== undefined).assertTrue();
      expect(MotionTokens.emphasizedAccelerate() !== undefined).assertTrue();
      expect(MotionTokens.standard() !== undefined).assertTrue();
      expect(MotionTokens.standardAccelerate() !== undefined).assertTrue();
    });

    it('copies the AppMotion cubic control points exactly', 0, () => {
      expect(MotionTokens.CUBIC_EMPHASIZED.length).assertEqual(4);
      expect(MotionTokens.CUBIC_EMPHASIZED[0]).assertEqual(0.2);
      expect(MotionTokens.CUBIC_EMPHASIZED[3]).assertEqual(1.0);
      expect(MotionTokens.CUBIC_EMPHASIZED_DECELERATE[0]).assertEqual(0.05);
      expect(MotionTokens.CUBIC_EMPHASIZED_DECELERATE[2]).assertEqual(0.1);
      expect(MotionTokens.CUBIC_EMPHASIZED_ACCELERATE[2]).assertEqual(0.8);
      expect(MotionTokens.CUBIC_EMPHASIZED_ACCELERATE[3]).assertEqual(0.15);
      expect(MotionTokens.CUBIC_STANDARD[0]).assertEqual(0.2);
      expect(MotionTokens.CUBIC_STANDARD_ACCELERATE[2]).assertEqual(1.0);
      expect(MotionTokens.CUBIC_STANDARD_ACCELERATE[3]).assertEqual(1.0);
    });
  });
}
