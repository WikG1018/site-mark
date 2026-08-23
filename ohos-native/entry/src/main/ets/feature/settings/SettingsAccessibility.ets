import { tr } from '../../shared/AppText';
import { UiTokens } from '../../shared/UiTokens';
import { WatermarkAccentOption, watermarkAccentOptions, watermarkAccentAccessibilityText, themeSeedAccessibilityText }
  from '../../shared/AccentAccessibility';

export { WatermarkAccentOption, watermarkAccentOptions, watermarkAccentAccessibilityText, themeSeedAccessibilityText };

export function settingsBackAccessibilityText(): string {
  return tr('返回', 'Back');
}

export function settingsConfirmationButtonHeight(): number {
  return UiTokens.TOUCH_TARGET;
}

export function diagnosticsConfirmAccessibilityText(): string {
  return tr('确认并选择保存位置', 'Confirm and choose save location');
}
