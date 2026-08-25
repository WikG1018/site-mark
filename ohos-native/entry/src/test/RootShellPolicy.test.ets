import { describe, expect, it } from '@ohos/hypium';
import { MotionPolicy } from '../main/ets/shared/MotionPolicy';
import { RootLifecycleCoordinator, RootShellPolicy, RootTabCoordinator } from
  '../main/ets/shared/RootShellPolicy';
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

    it('keeps overlay list viewport unpadded and puts dock clearance in content end offset', 0, () => {
      expect(RootShellPolicy.overlayListViewportBottomPadding()).assertEqual(0);
      expect(RootShellPolicy.overlayContentEndOffset())
        .assertEqual(RootShellPolicy.contentBottomInset());
      expect(RootShellPolicy.overlayContentEndOffset(36))
        .assertEqual(RootShellPolicy.contentBottomInset() + 36);
      expect(RootShellPolicy.overlayContentEndOffset(Number.NaN))
        .assertEqual(RootShellPolicy.contentBottomInset());
      expect(RootShellPolicy.overlayContentEndOffset(-8))
        .assertEqual(RootShellPolicy.contentBottomInset());
    });

    it('serializes rapid 0 to 1 to 2 requests and settles on the latest tab', 0, () => {
      const coordinator = new RootTabCoordinator(0);
      const first = coordinator.request(1);
      const queued = coordinator.request(2);

      expect(first.started).assertTrue();
      expect(first.targetIndex).assertEqual(1);
      expect(queued.started).assertFalse();

      const second = coordinator.finish(first.generation);
      expect(second.started).assertTrue();
      expect(second.targetIndex).assertEqual(2);
      expect(coordinator.finish(second.generation).started).assertFalse();
      expect(coordinator.currentIndex()).assertEqual(2);
    });

    it('keeps only the latest target while a tab transition is running', 0, () => {
      const coordinator = new RootTabCoordinator(0);
      const first = coordinator.request(1);
      coordinator.request(2);
      coordinator.request(0);
      coordinator.request(2);

      const latest = coordinator.finish(first.generation);
      expect(latest.started).assertTrue();
      expect(latest.targetIndex).assertEqual(2);
    });

    it('ignores repeated current tabs and cancels a queued target when current is requested again', 0, () => {
      const coordinator = new RootTabCoordinator(0);
      expect(coordinator.request(0).started).assertFalse();

      const first = coordinator.request(1);
      coordinator.request(2);
      expect(coordinator.request(1).started).assertFalse();
      expect(coordinator.finish(first.generation).started).assertFalse();
      expect(coordinator.currentIndex()).assertEqual(1);
    });

    it('ignores an animation finish callback after tab coordination is deactivated', 0, () => {
      const coordinator = new RootTabCoordinator(0);
      const first = coordinator.request(1);
      coordinator.deactivate();
      const replacement = coordinator.request(2);

      expect(coordinator.finish(first.generation).started).assertFalse();
      expect(replacement.started).assertTrue();
      expect(coordinator.finish(replacement.generation).started).assertFalse();
      expect(coordinator.currentIndex()).assertEqual(2);
    });

    it('uses idempotent lifecycle generations and rejects stale async completions', 0, () => {
      const lifecycle = new RootLifecycleCoordinator();
      const first = lifecycle.activate();
      expect(lifecycle.activate()).assertEqual(first);
      expect(lifecycle.isCurrent(first)).assertTrue();

      lifecycle.deactivate();
      const inactiveGeneration = lifecycle.generation();
      lifecycle.deactivate();
      expect(lifecycle.generation()).assertEqual(inactiveGeneration);
      expect(lifecycle.isCurrent(first)).assertFalse();

      const second = lifecycle.activate();
      expect(second).assertEqual(inactiveGeneration + 1);
      expect(lifecycle.isCurrent(second)).assertTrue();
    });

    it('single-flights motion reads and restarts after a stale generation completes', 0, () => {
      const lifecycle = new RootLifecycleCoordinator();
      const first = lifecycle.activate();
      expect(lifecycle.beginMotionRefresh(first)).assertTrue();
      expect(lifecycle.beginMotionRefresh(first)).assertFalse();

      lifecycle.deactivate();
      const second = lifecycle.activate();
      expect(lifecycle.beginMotionRefresh(second)).assertFalse();

      const stale = lifecycle.finishMotionRefresh(first);
      expect(stale.commit).assertFalse();
      expect(stale.restartGeneration).assertEqual(second);
      expect(lifecycle.beginMotionRefresh(second)).assertTrue();

      const current = lifecycle.finishMotionRefresh(second);
      expect(current.commit).assertTrue();
      expect(current.restartGeneration).assertEqual(0);
    });

    it('retains only the newest foreground generation across repeated motion refresh requests', 0, () => {
      const lifecycle = new RootLifecycleCoordinator();
      const first = lifecycle.activate();
      expect(lifecycle.beginMotionRefresh(first)).assertTrue();

      lifecycle.deactivate();
      const second = lifecycle.activate();
      expect(lifecycle.beginMotionRefresh(second)).assertFalse();
      lifecycle.deactivate();
      const latest = lifecycle.activate();
      expect(lifecycle.beginMotionRefresh(latest)).assertFalse();

      const stale = lifecycle.finishMotionRefresh(first);
      expect(stale.commit).assertFalse();
      expect(stale.restartGeneration).assertEqual(latest);
    });
  });
}
