import { tr } from './AppText';

export function choiceAccessibilityText(label: string, selected: boolean): string {
  return selected ? tr(`${label}，已选择`, `${label}, selected`) :
    tr(`${label}，未选择`, `${label}, not selected`);
}

export function lifecycleAccessibilityText(label: string, current: boolean): string {
  return current ? tr(`${label}，当前`, `${label}, current`) :
    tr(`${label}，非当前`, `${label}, not current`);
}

export function joinAccessibilityText(parts: string[]): string {
  return parts.filter((part: string): boolean => part.length > 0).join(tr('，', ', '));
}
