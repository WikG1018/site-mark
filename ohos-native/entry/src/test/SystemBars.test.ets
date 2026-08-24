import { describe, expect, it } from '@ohos/hypium';
import { SAFE_AREA_BOTTOM_VP, SAFE_AREA_TOP_VP, bottomInsetVp, topPaddingVp }
  from '../main/ets/shared/SystemBars';

export default function systemBarsTest(): void {
  describe('SystemBars', () => {
    it('exposes AppStorage keys for top and bottom safe area', 0, () => {
      expect(SAFE_AREA_TOP_VP).assertEqual('safeAreaTopVp');
      expect(SAFE_AREA_BOTTOM_VP).assertEqual('safeAreaBottomVp');
    });

    it('takes the larger of navigation and indicator bottom insets', 0, () => {
      expect(bottomInsetVp(48, 34)).assertEqual(48);
      expect(bottomInsetVp(24, 36)).assertEqual(36);
      expect(bottomInsetVp(0, 0)).assertEqual(0);
      expect(bottomInsetVp(12, 12)).assertEqual(12);
    });

    it('treats non-finite navigation or indicator values as zero', 0, () => {
      expect(bottomInsetVp(Number.NaN, 36)).assertEqual(36);
      expect(bottomInsetVp(48, Number.NaN)).assertEqual(48);
      expect(bottomInsetVp(Number.POSITIVE_INFINITY, 10)).assertEqual(10);
      expect(bottomInsetVp(-8, 20)).assertEqual(20);
      expect(bottomInsetVp(20, -4)).assertEqual(20);
      expect(bottomInsetVp(Number.NaN, Number.NaN)).assertEqual(0);
    });

    it('adds a finite inset to a finite base padding', 0, () => {
      expect(topPaddingVp(34, 20)).assertEqual(54);
      expect(topPaddingVp(0, 52)).assertEqual(52);
      expect(topPaddingVp(34, 0)).assertEqual(34);
    });

    it('treats non-finite inset or base as zero when adding padding', 0, () => {
      expect(topPaddingVp(Number.NaN, 20)).assertEqual(20);
      expect(topPaddingVp(34, Number.NaN)).assertEqual(34);
      expect(topPaddingVp(-8, 20)).assertEqual(20);
      expect(topPaddingVp(34, -4)).assertEqual(34);
    });
  });
}
