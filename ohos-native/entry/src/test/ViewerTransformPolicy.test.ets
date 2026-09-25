import { describe, expect, it } from '@ohos/hypium';
import { ViewerTransformPolicy } from '../main/ets/feature/records/ViewerTransformPolicy';

export default function viewerTransformPolicyTest(): void {
  describe('ViewerTransformPolicy', () => {
    it('keeps legal pan offsets untouched', 0, () => {
      expect(ViewerTransformPolicy.rubberBand(40, 100)).assertEqual(40);
      expect(ViewerTransformPolicy.rubberBand(-40, 100)).assertEqual(-40);
      expect(ViewerTransformPolicy.rubberBand(100, 100)).assertEqual(100);
    });

    it('rubber-bands past the bound at the 0.25 rate', 0, () => {
      expect(ViewerTransformPolicy.rubberBand(200, 100)).assertEqual(125);
      expect(ViewerTransformPolicy.rubberBand(-200, 100)).assertEqual(-125);
      expect(ViewerTransformPolicy.rubberBand(10, 0)).assertEqual(0);
      expect(ViewerTransformPolicy.rubberBand(Number.NaN, 100)).assertEqual(0);
    });

    it('derives release drift from the tracked velocity', 0, () => {
      expect(ViewerTransformPolicy.INERTIA_FACTOR).assertEqual(0.18);
      expect(ViewerTransformPolicy.inertiaOffset(1000)).assertEqual(180);
      expect(ViewerTransformPolicy.inertiaOffset(-500)).assertEqual(-90);
      expect(ViewerTransformPolicy.inertiaOffset(Number.NaN)).assertEqual(0);
      expect(ViewerTransformPolicy.inertiaOffset(Number.POSITIVE_INFINITY)).assertEqual(0);
    });

    it('falls back to 2x when the content rect is unmeasured', 0, (): void => {
      expect(ViewerTransformPolicy.doubleTapTarget(null)).assertEqual(2.0);
    });

    it('clamps measured targets into the double-tap band', 0, () => {
      expect(ViewerTransformPolicy.doubleTapTarget(1.5)).assertEqual(1.5);
      expect(ViewerTransformPolicy.doubleTapTarget(1.05)).assertEqual(1.2);
      expect(ViewerTransformPolicy.doubleTapTarget(4)).assertEqual(2.5);
      expect(ViewerTransformPolicy.doubleTapTarget(Number.NaN)).assertEqual(2.0);
    });
  });
}
