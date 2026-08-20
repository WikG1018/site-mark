import { describe, expect, it } from '@ohos/hypium';
import { ScreenActionCoordinator } from '../main/ets/shared/ScreenActionCoordinator';

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
  });
}
