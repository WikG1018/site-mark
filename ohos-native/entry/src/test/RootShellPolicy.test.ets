import { describe, expect, it } from '@ohos/hypium';
import { MotionPolicy } from '../main/ets/shared/MotionPolicy';
import { RootShellPolicy } from '../main/ets/shared/RootShellPolicy';
import { UiTokens } from '../main/ets/shared/UiTokens';

export default function rootShellPolicyTest(): void {
  describe('RootShellPolicy', () => {
    it('clamps dock selection into predictable third-width slots', 0, () => {
      expect(RootShellPolicy.dockSelectedOffset(300, -1)).assertEqual(0);
      expect(RootShellPolicy.dockSelectedOffset(300, 0)).assertEqual(0);
      expect(RootShellPolicy.dockSelectedOffset(300, 1)).assertEqual(100);
      expect(RootShellPolicy.dockSelectedOffset(300, 2)).assertEqual(200);
      expect(RootShellPolicy.dockSelectedOffset(300, 7)).assertEqual(200);
      expect(RootShellPolicy.dockSelectedOffset(300, Number.NaN)).assertEqual(0);
      expect(RootShellPolicy.dockSelectedOffset(0, 1)).assertEqual(0);
    });

    it('moves right tabs forward left tabs backward and ignores repeats', 0, () => {
      const right = RootShellPolicy.transition(0, 1);
      const left = RootShellPolicy.transition(2, 0);
      const repeat = RootShellPolicy.transition(1, 1);

      expect(right.changed).assertTrue();
      expect(right.targetIndex).assertEqual(1);
      expect(right.direction).assertEqual(1);
      expect(left.changed).assertTrue();
      expect(left.targetIndex).assertEqual(0);
      expect(left.direction).assertEqual(-1);
      expect(repeat.changed).assertFalse();
      expect(repeat.targetIndex).assertEqual(1);
      expect(repeat.direction).assertEqual(0);

      const firstRapidTarget = RootShellPolicy.transition(0, 1).targetIndex;
      const finalRapidTarget = RootShellPolicy.transition(firstRapidTarget, 2).targetIndex;
      expect(finalRapidTarget).assertEqual(2);
      expect(RootShellPolicy.transition(2, 99).changed).assertFalse();

      const deferred = RootShellPolicy.transition(1, 2, true);
      expect(deferred.changed).assertTrue();
      expect(deferred.deferUntilSettled).assertTrue();
      expect(deferred.targetIndex).assertEqual(2);
    });

    it('uses standard motion normally and removes motion and blur when reduced', 0, () => {
      MotionPolicy.reduceMotion = false;
      const normal = RootShellPolicy.motion(1);
      expect(normal.pageDuration).assertEqual(UiTokens.MOTION_STANDARD);
      expect(normal.fadeDuration).assertEqual(UiTokens.MOTION_STANDARD);
      expect(normal.dockDuration).assertEqual(UiTokens.MOTION_STANDARD);
      expect(normal.enterX).assertEqual(24);
      expect(normal.exitX).assertEqual(-16);
      expect(normal.dockBlur).assertEqual(24);
      expect(normal.selectionBlur).assertEqual(14);
      const normalLeft = RootShellPolicy.motion(-1);
      expect(normalLeft.enterX).assertEqual(-24);
      expect(normalLeft.exitX).assertEqual(16);

      MotionPolicy.reduceMotion = true;
      const reduced = RootShellPolicy.motion(-1);
      expect(reduced.pageDuration).assertEqual(0);
      expect(reduced.fadeDuration).assertEqual(0);
      expect(reduced.dockDuration).assertEqual(0);
      expect(reduced.enterX).assertEqual(0);
      expect(reduced.exitX).assertEqual(0);
      expect(reduced.dockBlur).assertEqual(0);
      expect(reduced.selectionBlur).assertEqual(0);
      MotionPolicy.reduceMotion = false;
    });

    it('centralizes dock dimensions and root content bottom inset', 0, () => {
      expect(RootShellPolicy.dockHeight()).assertEqual(64);
      expect(RootShellPolicy.dockHeight()).assertEqual(UiTokens.DOCK_HEIGHT);
      expect(RootShellPolicy.dockHorizontalMargin()).assertEqual(14);
      expect(RootShellPolicy.dockBottomMargin()).assertEqual(12);
      expect(RootShellPolicy.contentBottomInset()).assertEqual(UiTokens.DOCK_HEIGHT + 28);
    });
  });
}
