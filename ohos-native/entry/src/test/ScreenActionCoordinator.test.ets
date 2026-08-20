import { describe, expect, it } from '@ohos/hypium';
import { ScreenActionCoordinator, ScreenLifecycleActionCoordinator, ScreenRequestCoordinator }
  from '../main/ets/shared/ScreenActionCoordinator';

export default function screenActionCoordinatorTest(): void {
  describe('ScreenActionCoordinator', () => {
    it('rejects duplicate actions until the current action finishes', 0, () => {
      const coordinator = new ScreenActionCoordinator();
      const token = coordinator.begin();

      expect(token === null).assertFalse();
      expect(coordinator.isBusy()).assertTrue();
      expect(coordinator.begin() === null).assertTrue();
      expect(coordinator.finish(token as number)).assertTrue();
      expect(coordinator.isBusy()).assertFalse();
      expect(coordinator.begin() === null).assertFalse();
    });

    it('rejects a stale completion after the screen is invalidated', 0, () => {
      const coordinator = new ScreenActionCoordinator();
      const token = coordinator.begin() as number;

      coordinator.invalidate();

      expect(coordinator.isCurrent(token)).assertFalse();
      expect(coordinator.finish(token)).assertFalse();
      expect(coordinator.isBusy()).assertFalse();
    });

    it('rejects work while inactive and accepts fresh work after reactivation', 0, () => {
      const coordinator = new ScreenLifecycleActionCoordinator();
      coordinator.invalidate();

      expect(coordinator.begin() === null).assertTrue();
      coordinator.activate();
      const token = coordinator.begin();

      expect(token === null).assertFalse();
      expect(coordinator.isCurrent(token as number)).assertTrue();
    });

    it('accepts only the newest request while a page remains active', 0, () => {
      const coordinator: ScreenRequestCoordinator = new ScreenRequestCoordinator();
      coordinator.activate();
      const first: number = coordinator.begin();
      const second: number = coordinator.begin();

      expect(coordinator.isCurrent(first)).assertFalse();
      expect(coordinator.isCurrent(second)).assertTrue();
      coordinator.deactivate();
      expect(coordinator.isCurrent(second)).assertFalse();
      expect(coordinator.begin()).assertEqual(-1);
    });
  });
}
