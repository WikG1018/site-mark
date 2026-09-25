import { describe, expect, it } from '@ohos/hypium';
import { UiTokens } from '../main/ets/shared/UiTokens';
import { AccentSwatches } from '../main/ets/shared/AccentSwatches';

export default function uiTokensTest(): void {
  describe('UiTokens on-color contrast', () => {
    it('uses dark labels on the bright accents users can pick', 0, () => {
      expect(UiTokens.onColorFor(0xFFF9A825)).assertEqual('#1B1B1B');
      expect(UiTokens.onColorFor(0xFFEF6C00)).assertEqual('#1B1B1B');
      expect(UiTokens.onColorFor(0xFF37C58B)).assertEqual('#1B1B1B');
    });

    it('keeps white labels on the dark accents', 0, () => {
      expect(UiTokens.onColorFor(0xFF1565C0)).assertEqual('#FFFFFF');
      expect(UiTokens.onColorFor(0xFFC62828)).assertEqual('#FFFFFF');
      expect(UiTokens.onColorFor(0xFF6A1B9A)).assertEqual('#FFFFFF');
      expect(UiTokens.onColorFor(0xFFAD1457)).assertEqual('#FFFFFF');
      expect(UiTokens.onColorFor(0xFF283593)).assertEqual('#FFFFFF');
    });

    it('applies ON_PRIMARY together with the accent', 0, () => {
      UiTokens.apply(false, 0xFFF9A825);
      expect(UiTokens.PRIMARY).assertEqual('#fff9a825');
      expect(UiTokens.ON_PRIMARY).assertEqual('#1B1B1B');
      UiTokens.apply(false, AccentSwatches.defaultArgb());
      expect(UiTokens.PRIMARY).assertEqual('#ff37c58b');
      expect(UiTokens.ON_PRIMARY).assertEqual('#1B1B1B');
      UiTokens.apply(false, 0xFF1565C0);
      expect(UiTokens.ON_PRIMARY).assertEqual('#FFFFFF');
    });

    it('applies ON_DANGER together with the danger color', 0, () => {
      UiTokens.apply(true, AccentSwatches.defaultArgb());
      expect(UiTokens.DANGER).assertEqual('#FFB4AB');
      expect(UiTokens.ON_DANGER).assertEqual('#410E0B');
      UiTokens.apply(false, AccentSwatches.defaultArgb());
      expect(UiTokens.DANGER).assertEqual('#B3261E');
      expect(UiTokens.ON_DANGER).assertEqual('#FFFFFF');
    });

    it('keeps the legacy green label white before any accent is applied', 0, () => {
      expect(UiTokens.onColorFor(0xFF176B55)).assertEqual('#FFFFFF');
    });
  });

  describe('UiTokens material tokens', () => {
    it('exposes the six-step AppRadius scale', 0, () => {
      expect(UiTokens.RADIUS_XS).assertEqual(8);
      expect(UiTokens.RADIUS_SM).assertEqual(12);
      expect(UiTokens.RADIUS_MD).assertEqual(16);
      expect(UiTokens.RADIUS_LG).assertEqual(20);
      expect(UiTokens.RADIUS_XL).assertEqual(24);
    });

    it('lands the legacy radius aliases on the scale', 0, () => {
      expect(UiTokens.CARD_RADIUS).assertEqual(UiTokens.RADIUS_LG);
      expect(UiTokens.CONTROL_RADIUS).assertEqual(UiTokens.RADIUS_SM);
    });

    it('derives the glass fill from the surface color per recipe tier', 0, () => {
      expect(UiTokens.GLASS_OPACITY).assertEqual(0.58);
      expect(UiTokens.GLASS_OPACITY_NO_BLUR).assertEqual(0.68);
      UiTokens.apply(false, AccentSwatches.defaultArgb());
      expect(UiTokens.SURFACE).assertEqual('#F9FCF9');
      expect(UiTokens.GLASS).assertEqual('#94F9FCF9');
      expect(UiTokens.GLASS_STRONG).assertEqual('#ADF9FCF9');
      expect(UiTokens.DOCK).assertEqual(UiTokens.GLASS);
      UiTokens.apply(true, AccentSwatches.defaultArgb());
      expect(UiTokens.SURFACE).assertEqual('#171D19');
      expect(UiTokens.GLASS).assertEqual('#94171D19');
      expect(UiTokens.GLASS_STRONG).assertEqual('#AD171D19');
      expect(UiTokens.DOCK).assertEqual(UiTokens.GLASS);
    });

    it('keeps one floating-chrome shadow recipe', 0, () => {
      UiTokens.apply(false, AccentSwatches.defaultArgb());
      expect(UiTokens.CHROME_SHADOW_COLOR).assertEqual('#14000000');
      expect(UiTokens.CHROME_SHADOW_BLUR).assertEqual(12);
      expect(UiTokens.CHROME_SHADOW_OFFSET_Y).assertEqual(3);
      UiTokens.apply(true, AccentSwatches.defaultArgb());
      expect(UiTokens.CHROME_SHADOW_COLOR).assertEqual('#24000000');
      expect(UiTokens.CHROME_SHADOW_BLUR).assertEqual(14);
    });
  });
}
