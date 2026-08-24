import { describe, expect, it } from '@ohos/hypium';
import { AccentSwatch, AccentSwatches } from '../main/ets/shared/AccentSwatches';

export default function accentSwatchesTest(): void {
  describe('AccentSwatches', () => {
    it('exposes nine Flutter-aligned swatches in order with the new green default', 0, () => {
      const values: AccentSwatch[] = AccentSwatches.values();
      expect(values.length).assertEqual(9);
      expect(values.map((row: AccentSwatch): string => row.id).join('|'))
        .assertEqual('green|blue|orange|red|purple|teal|pink|yellow|indigo');
      expect(values.map((row: AccentSwatch): string => row.argb.toString(16).toUpperCase()).join('|'))
        .assertEqual('FF37C58B|FF1565C0|FFEF6C00|FFC62828|FF6A1B9A|FF00838F|FFAD1457|FFF9A825|FF283593');
      expect(values[0].argb).assertEqual(AccentSwatches.defaultArgb());
      expect(AccentSwatches.defaultArgb()).assertEqual(0xFF37C58B);
    });

    it('treats table members as contained and unknown colors as absent', 0, () => {
      expect(AccentSwatches.contains(0xFF37C58B)).assertTrue();
      expect(AccentSwatches.contains(0xFF00838F)).assertTrue();
      expect(AccentSwatches.contains(0xFF176B55)).assertFalse();
      expect(AccentSwatches.contains(0xFF2E7D61)).assertFalse();
    });

    it('maps legacy greens by alias before Euclidean distance so they are not teal', 0, () => {
      expect(AccentSwatches.nearest(0xFF37C58B)).assertEqual(0xFF37C58B);
      expect(AccentSwatches.nearest(0xFF176B55)).assertEqual(0xFF37C58B);
      expect(AccentSwatches.nearest(0xFF2E7D61)).assertEqual(0xFF37C58B);
      expect(AccentSwatches.nearest(0xFF176B55) === 0xFF00838F).assertFalse();
      expect(AccentSwatches.nearest(0xFF2E7D61) === 0xFF00838F).assertFalse();
      expect(AccentSwatches.nearest(Number.NaN)).assertEqual(0xFF37C58B);
      expect(AccentSwatches.nearest(Number.POSITIVE_INFINITY)).assertEqual(0xFF37C58B);
    });

    it('returns distinct bilingual labels and blank for unknown values', 0, () => {
      const chinese: string[] = AccentSwatches.values()
        .map((row: AccentSwatch): string => AccentSwatches.label(row.argb, false));
      const english: string[] = AccentSwatches.values()
        .map((row: AccentSwatch): string => AccentSwatches.label(row.argb, true));
      expect(chinese.join('|')).assertEqual('绿色|蓝色|橙色|红色|紫色|青色|粉色|黄色|靛蓝');
      expect(english.join('|')).assertEqual('Green|Blue|Orange|Red|Purple|Teal|Pink|Yellow|Indigo');
      expect(new Set<string>(chinese).size).assertEqual(9);
      expect(new Set<string>(english).size).assertEqual(9);
      expect(AccentSwatches.label(0xFF176B55, false)).assertEqual('');
      expect(AccentSwatches.label(0xFF2E7D61, true)).assertEqual('');
    });

    it('formats RGB hex without alpha for project choice backgrounds', 0, () => {
      expect(AccentSwatches.toRgbHex(0xFF37C58B)).assertEqual('#37C58B');
      expect(AccentSwatches.toRgbHex(0xFF1565C0)).assertEqual('#1565C0');
    });
  });
}
