export class AccentSwatch {
  argb: number;
  id: string;

  constructor(argb: number, id: string) {
    this.argb = argb;
    this.id = id;
  }
}

export class AccentSwatches {
  private static readonly SWATCHES: AccentSwatch[] = [
    new AccentSwatch(0xFF37C58B, 'green'),
    new AccentSwatch(0xFF1565C0, 'blue'),
    new AccentSwatch(0xFFEF6C00, 'orange'),
    new AccentSwatch(0xFFC62828, 'red'),
    new AccentSwatch(0xFF6A1B9A, 'purple'),
    new AccentSwatch(0xFF00838F, 'teal'),
    new AccentSwatch(0xFFAD1457, 'pink'),
    new AccentSwatch(0xFFF9A825, 'yellow'),
    new AccentSwatch(0xFF283593, 'indigo')
  ];

  private static readonly LABELS_ZH: string[] = [
    '绿色', '蓝色', '橙色', '红色', '紫色', '青色', '粉色', '黄色', '靛蓝'
  ];

  private static readonly LABELS_EN: string[] = [
    'Green', 'Blue', 'Orange', 'Red', 'Purple', 'Teal', 'Pink', 'Yellow', 'Indigo'
  ];

  private static readonly LEGACY_GREEN: number[] = [0xFF176B55, 0xFF2E7D61];

  static values(): AccentSwatch[] {
    return AccentSwatches.SWATCHES;
  }

  static defaultArgb(): number {
    return AccentSwatches.SWATCHES[0].argb;
  }

  static contains(argb: number): boolean {
    const needle: number = argb >>> 0;
    return AccentSwatches.SWATCHES.some((row: AccentSwatch): boolean => (row.argb >>> 0) === needle);
  }

  static nearest(argb: number): number {
    if (!Number.isFinite(argb)) {
      return AccentSwatches.defaultArgb();
    }
    const needle: number = argb >>> 0;
    for (let i = 0; i < AccentSwatches.LEGACY_GREEN.length; i++) {
      if ((AccentSwatches.LEGACY_GREEN[i] >>> 0) === needle) {
        return AccentSwatches.defaultArgb();
      }
    }
    if (AccentSwatches.contains(needle)) {
      return needle;
    }
    const nr: number = (needle >> 16) & 0xFF;
    const ng: number = (needle >> 8) & 0xFF;
    const nb: number = needle & 0xFF;
    let best: number = AccentSwatches.defaultArgb();
    let bestDist: number = Number.POSITIVE_INFINITY;
    const rows: AccentSwatch[] = AccentSwatches.SWATCHES;
    for (let i = 0; i < rows.length; i++) {
      const value: number = rows[i].argb >>> 0;
      const dr: number = nr - ((value >> 16) & 0xFF);
      const dg: number = ng - ((value >> 8) & 0xFF);
      const db: number = nb - (value & 0xFF);
      const dist: number = dr * dr + dg * dg + db * db;
      if (dist < bestDist) {
        bestDist = dist;
        best = rows[i].argb;
      }
    }
    return best;
  }

  static label(argb: number, english: boolean): string {
    const needle: number = argb >>> 0;
    const rows: AccentSwatch[] = AccentSwatches.SWATCHES;
    for (let i = 0; i < rows.length; i++) {
      if ((rows[i].argb >>> 0) === needle) {
        return english ? AccentSwatches.LABELS_EN[i] : AccentSwatches.LABELS_ZH[i];
      }
    }
    return '';
  }

  static toRgbHex(argb: number): string {
    const rgb: number = (argb >>> 0) & 0xFFFFFF;
    return `#${rgb.toString(16).toUpperCase().padStart(6, '0')}`;
  }
}
