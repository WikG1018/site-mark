import { describe, expect, it } from '@ohos/hypium';
import { AppFont } from '../main/ets/shared/AppFont';

export default function appFontTest(): void {
  describe('AppFont', () => {
    it('names the embedded MiSans families and sources', 0, () => {
      expect(AppFont.FAMILY).assertEqual('MiSans');
      expect(AppFont.FAMILY_MEDIUM).assertEqual('MiSans Medium');
      expect(AppFont.REGULAR_SRC).assertEqual('/rawfile/font/MiSans-Regular.ttf');
      expect(AppFont.MEDIUM_SRC).assertEqual('/rawfile/font/MiSans-Medium.ttf');
    });

    it('never throws when the runtime rejects registration', 0, () => {
      // Outside a window stage the font API may refuse; typography must
      // degrade to the system font instead of crashing.
      AppFont.register();
      expect(true).assertTrue();
    });
  });
}
