export const SAFE_AREA_TOP_VP: string = 'safeAreaTopVp';
export const SAFE_AREA_BOTTOM_VP: string = 'safeAreaBottomVp';

function finiteOrZero(value: number): number {
  return Number.isFinite(value) && value > 0 ? value : 0;
}

export function bottomInsetVp(navigationVp: number, indicatorVp: number): number {
  return Math.max(finiteOrZero(navigationVp), finiteOrZero(indicatorVp));
}

export function topPaddingVp(insetVp: number, baseVp: number): number {
  return finiteOrZero(insetVp) + finiteOrZero(baseVp);
}
