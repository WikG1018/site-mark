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
  return [
    new WatermarkAccentOption(0xFF2E7D61, '深绿色', 'Deep green'),
    new WatermarkAccentOption(0xFF1565C0, '蓝色', 'Blue'),
    new WatermarkAccentOption(0xFFC05A24, '橙色', 'Orange'),
    new WatermarkAccentOption(0xFF7B4DA8, '紫色', 'Purple'),
    new WatermarkAccentOption(0xFF37474F, '深灰色', 'Dark gray')
  ];
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
