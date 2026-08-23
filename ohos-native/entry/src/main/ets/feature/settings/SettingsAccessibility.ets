import { AccentSwatch, AccentSwatches } from '../../shared/AccentSwatches';
import { tr } from '../../shared/AppText';
import { UiTokens } from '../../shared/UiTokens';

export class WatermarkAccentOption {
  color: number;
  chineseName: string;
  englishName: string;

  constructor(color: number, chineseName: string, englishName: string) {
    this.color = color;
    this.chineseName = chineseName;
    this.englishName = englishName;
  }
}

export function watermarkAccentOptions(): WatermarkAccentOption[] {
  return AccentSwatches.values().map((swatch: AccentSwatch): WatermarkAccentOption =>
    new WatermarkAccentOption(
      swatch.argb,
      AccentSwatches.label(swatch.argb, false),
      AccentSwatches.label(swatch.argb, true)));
}

export function themeSeedAccessibilityText(option: WatermarkAccentOption, selected: boolean): string {
  return selected ?
    tr(`应用主题色 ${option.chineseName}，已选择`, `App theme color ${option.englishName}, selected`) :
    tr(`应用主题色 ${option.chineseName}，未选择`, `App theme color ${option.englishName}, not selected`);
}

export function settingsBackAccessibilityText(): string {
  return tr('返回', 'Back');
}

export function settingsConfirmationButtonHeight(): number {
  return UiTokens.TOUCH_TARGET;
}

export function diagnosticsConfirmAccessibilityText(): string {
  return tr('确认并选择保存位置', 'Confirm and choose save location');
}

export function watermarkAccentAccessibilityText(option: WatermarkAccentOption, selected: boolean): string {
  return selected ? tr(`${option.chineseName}，已选择`, `${option.englishName}, selected`) :
    tr(`${option.chineseName}，未选择`, `${option.englishName}, not selected`);
}
