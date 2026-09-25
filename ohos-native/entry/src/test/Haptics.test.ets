import { describe, expect, it } from '@ohos/hypium';
import { Haptics } from '../main/ets/shared/Feedback';

export default function hapticsTest(): void {
  describe('Haptics tiers', () => {
    it('keeps the Android tier durations', 0, () => {
      expect(Haptics.SELECTION_CLICK_MS).assertEqual(16);
      expect(Haptics.LIGHT_IMPACT_MS).assertEqual(16);
      expect(Haptics.MEDIUM_IMPACT_MS).assertEqual(32);
      expect(Haptics.HEAVY_IMPACT_MS).assertEqual(48);
    });

    it('orders the tiers', 0, () => {
      expect(Haptics.SELECTION_CLICK_MS <= Haptics.MEDIUM_IMPACT_MS).assertTrue();
      expect(Haptics.MEDIUM_IMPACT_MS < Haptics.HEAVY_IMPACT_MS).assertTrue();
    });
  });
}
