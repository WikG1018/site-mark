import { describe, expect, it } from '@ohos/hypium';
import { ScrollChromeCoordinator, ScrollChromePolicy } from '../main/ets/shared/ScrollChromePolicy';

export default function scrollChromePolicyTest(): void {
  describe('ScrollChromePolicy', () => {
    it('starts visible', 0, () => {
      expect(new ScrollChromePolicy().visible).assertTrue();
    });

    it('ignores jitter smaller than the hide threshold', 0, () => {
      const policy = new ScrollChromePolicy();
      expect(policy.apply(ScrollChromePolicy.HIDE_THRESHOLD - 1, 80)).assertFalse();
      expect(policy.visible).assertTrue();
    });

    it('hides after downward deltas accumulate past the threshold', 0, () => {
      const policy = new ScrollChromePolicy();
      const half = ScrollChromePolicy.HIDE_THRESHOLD / 2;
      expect(policy.apply(half, 80)).assertFalse();
      expect(policy.visible).assertTrue();
      expect(policy.apply(half, 80 + half)).assertTrue();
      expect(policy.visible).assertFalse();
    });

    it('shows again after an upward delta past the show threshold', 0, () => {
      const policy = new ScrollChromePolicy();
      policy.apply(40, 200);
      expect(policy.apply(-ScrollChromePolicy.SHOW_THRESHOLD, 160)).assertTrue();
      expect(policy.visible).assertTrue();
    });

    it('stays visible while forceVisible even on a large downward scroll', 0, () => {
      const policy = new ScrollChromePolicy();
      expect(policy.apply(80, 400, true)).assertFalse();
      expect(policy.visible).assertTrue();
    });

    it('stays visible near the top of the list', 0, () => {
      const policy = new ScrollChromePolicy();
      policy.apply(80, 400);
      expect(policy.apply(20, ScrollChromePolicy.TOP_REVEAL_EXTENT)).assertTrue();
      expect(policy.visible).assertTrue();
    });

    it('reset shows chrome and clears a pending hide', 0, () => {
      const policy = new ScrollChromePolicy();
      policy.apply(ScrollChromePolicy.HIDE_THRESHOLD - 1, 80);
      policy.apply(40, 200);
      expect(policy.reset()).assertTrue();
      expect(policy.visible).assertTrue();
      expect(policy.apply(ScrollChromePolicy.HIDE_THRESHOLD - 1, 80)).assertFalse();
      expect(policy.visible).assertTrue();
    });

    it('ignores non-finite deltas and offsets', 0, () => {
      const policy = new ScrollChromePolicy();
      expect(policy.apply(Number.NaN, 80)).assertFalse();
      expect(policy.apply(40, Number.POSITIVE_INFINITY)).assertFalse();
      expect(policy.visible).assertTrue();
    });
  });

  describe('ScrollChromeCoordinator', () => {
    it('keeps chrome visible while a force reason is active', 0, () => {
      const chrome = new ScrollChromeCoordinator();
      chrome.setForce('search', true);
      chrome.applyOffset(0);
      chrome.applyOffset(120);
      expect(chrome.isVisible()).assertTrue();
      chrome.setForce('search', false);
      expect(chrome.isVisible()).assertTrue();
    });

    it('hides after a downward offset change and shows again on reset', 0, () => {
      const chrome = new ScrollChromeCoordinator();
      chrome.applyOffset(0);
      chrome.applyOffset(40);
      expect(chrome.isVisible()).assertFalse();
      chrome.reset();
      expect(chrome.isVisible()).assertTrue();
      expect(chrome.hiddenTranslateY(80)).assertEqual(0);
    });
  });
}
