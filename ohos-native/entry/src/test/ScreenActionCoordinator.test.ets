import { describe, expect, it } from '@ohos/hypium';
import { ScreenActionCoordinator, ScreenLifecycleActionCoordinator, ScreenRequestCoordinator }
  from '../main/ets/shared/ScreenActionCoordinator';

class DeferredText {
  readonly promise: Promise<string>;
  private resolveValue: (value: string) => void = (_value: string): void => {};

  constructor() {
    this.promise = new Promise<string>((resolve: (value: string) => void): void => {
      this.resolveValue = resolve;
    });
  }

  resolve(value: string): void {
    this.resolveValue(value);
  }
}

class DeferredNumber {
  readonly promise: Promise<number>;
  private resolveValue: (value: number) => void = (_value: number): void => {};

  constructor() {
    this.promise = new Promise<number>((resolve: (value: number) => void): void => {
      this.resolveValue = resolve;
    });
  }

  resolve(value: number): void {
    this.resolveValue(value);
  }
}

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

    it('keeps the side effect locked across page epochs until the old action finishes', 0, () => {
      const coordinator = new ScreenLifecycleActionCoordinator();
      coordinator.activate();
      const oldToken = coordinator.begin() as number;

      coordinator.invalidate();
      coordinator.activate();

      expect(coordinator.begin() === null).assertTrue();
      expect(coordinator.finish(oldToken)).assertFalse();
      const newToken = coordinator.begin();
      expect(newToken === null).assertFalse();
      expect(coordinator.finish(newToken as number)).assertTrue();
    });

    it('does not let a repeated old completion clear a newer action lock', 0, () => {
      const coordinator = new ScreenLifecycleActionCoordinator();
      coordinator.activate();
      const oldToken = coordinator.begin() as number;
      coordinator.invalidate();
      coordinator.activate();

      expect(coordinator.finish(oldToken)).assertFalse();
      const newToken = coordinator.begin() as number;
      expect(coordinator.finish(oldToken)).assertFalse();
      expect(coordinator.begin() === null).assertTrue();
      expect(coordinator.finish(newToken)).assertTrue();
    });

    it('notifies a re-entered page only after the inherited action becomes idle', 0, async () => {
      const coordinator = new ScreenLifecycleActionCoordinator();
      coordinator.activate();
      const oldToken: number = coordinator.begin() as number;
      coordinator.invalidate();
      coordinator.activate();
      let idleResolved: boolean = false;

      const idle: Promise<void> = coordinator.whenIdle().then((): void => {
        idleResolved = true;
      });
      expect(idleResolved).assertFalse();
      coordinator.finish(oldToken);
      await idle;
      expect(idleResolved).assertTrue();
      expect(coordinator.isBusy()).assertFalse();
    });

    it('serializes delayed appearance or notification writes across leave and re-enter', 0, async () => {
      const coordinator = new ScreenLifecycleActionCoordinator();
      const firstWrite = new DeferredText();
      let calls: number = 0;
      let persisted: string = 'initial';
      let visible: string = 'initial';
      let staleCommitCount: number = 0;
      let reconcileCount: number = 0;
      coordinator.activate();

      const write = async (result: Promise<string>): Promise<boolean> => {
        const token: number | null = coordinator.begin();
        if (token === null) return false;
        calls += 1;
        const committed: string = await result;
        persisted = committed;
        if (coordinator.isCurrent(token)) {
          visible = committed;
          staleCommitCount += 1;
        }
        coordinator.finish(token);
        return true;
      };

      const oldOperation: Promise<boolean> = write(firstWrite.promise);
      coordinator.invalidate();
      coordinator.activate();
      const reconcile: Promise<void> = coordinator.whenIdle().then((): void => {
        if (!coordinator.isActive()) return;
        visible = persisted;
        reconcileCount += 1;
      });
      const blockedOperation: boolean = await write(Promise.resolve('new'));

      expect(blockedOperation).assertFalse();
      expect(calls).assertEqual(1);
      firstWrite.resolve('old');
      await oldOperation;
      await reconcile;
      expect(persisted).assertEqual('old');
      expect(visible).assertEqual('old');
      expect(staleCommitCount).assertEqual(0);
      expect(reconcileCount).assertEqual(1);

      await write(Promise.resolve('new'));
      expect(calls).assertEqual(2);
      expect(persisted).assertEqual('new');
      expect(visible).assertEqual('new');
      expect(staleCommitCount).assertEqual(1);
    });

    it('runs only one restore while its chooser is still pending', 0, async () => {
      const coordinator = new ScreenLifecycleActionCoordinator();
      const restoreResult = new DeferredNumber();
      let calls: number = 0;
      let restoredProjects: number = 0;
      coordinator.activate();

      const restore = async (): Promise<boolean> => {
        const token: number | null = coordinator.begin();
        if (token === null) return false;
        calls += 1;
        const count: number = await restoreResult.promise;
        if (coordinator.isCurrent(token)) restoredProjects = count;
        coordinator.finish(token);
        return true;
      };

      const first: Promise<boolean> = restore();
      const second: boolean = await restore();
      expect(second).assertFalse();
      expect(calls).assertEqual(1);
      restoreResult.resolve(3);
      await first;
      expect(restoredProjects).assertEqual(3);
      expect(calls).assertEqual(1);
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
