import { describe, expect, it } from '@ohos/hypium';
import { BackAction, BackCoordinator, BackDispatcher, ScreenLoadCoordinator, ScreenLoadStatus }
  from '../main/ets/shared/ScreenUiStabilityCoordinator';

class ProjectValue {
  readonly id: string;

  constructor(id: string) {
    this.id = id;
  }
}

export default function screenUiStabilityTest(): void {
  describe('Screen UI stability', () => {
    it('consumes back while a batch action is busy before changing page state', 0, () => {
      expect(BackCoordinator.next({ busy: true, selection: true, confirmation: true,
        filter: true, search: true })).assertEqual(BackAction.CONSUME);
    });

    it('closes transient page state in a stable priority before navigation', 0, () => {
      expect(BackCoordinator.next({ busy: false, selection: true, confirmation: true,
        filter: true, search: true })).assertEqual(BackAction.EXIT_SELECTION);
      expect(BackCoordinator.next({ busy: false, selection: false, confirmation: true,
        filter: true, search: true })).assertEqual(BackAction.CLOSE_CONFIRMATION);
      expect(BackCoordinator.next({ busy: false, selection: false, confirmation: false,
        filter: true, search: true })).assertEqual(BackAction.CLOSE_FILTER);
      expect(BackCoordinator.next({ busy: false, selection: false, confirmation: false,
        filter: false, search: true })).assertEqual(BackAction.CLEAR_SEARCH);
      expect(BackCoordinator.next({ busy: false, selection: false, confirmation: false,
        filter: false, search: false })).assertEqual(BackAction.NAVIGATE);
    });

    it('dispatches root back only to the currently registered root branch', 0, () => {
      const dispatcher = new BackDispatcher();
      let oldCalls: number = 0;
      let currentCalls: number = 0;
      const oldToken = dispatcher.register((): boolean => { oldCalls += 1; return true; });
      const currentToken = dispatcher.register((): boolean => { currentCalls += 1; return true; });

      dispatcher.unregister(oldToken);
      expect(dispatcher.handle()).assertTrue();
      expect(oldCalls).assertEqual(0);
      expect(currentCalls).assertEqual(1);
      dispatcher.unregister(currentToken);
      expect(dispatcher.handle()).assertFalse();
    });

    it('distinguishes a missing project from a failed request', 0, () => {
      const coordinator = new ScreenLoadCoordinator<ProjectValue>();
      coordinator.activate();
      const missingToken = coordinator.begin();

      expect(coordinator.resolve(missingToken, null)).assertTrue();
      expect(coordinator.status()).assertEqual(ScreenLoadStatus.MISSING);
      const errorToken = coordinator.begin();
      expect(coordinator.reject(errorToken)).assertTrue();
      expect(coordinator.status()).assertEqual(ScreenLoadStatus.ERROR);
    });

    it('rejects stale load completions after retry or page deactivation', 0, () => {
      const coordinator = new ScreenLoadCoordinator<ProjectValue>();
      coordinator.activate();
      const staleToken = coordinator.begin();
      const currentToken = coordinator.begin();

      expect(coordinator.resolve(staleToken, new ProjectValue('stale'))).assertFalse();
      expect(coordinator.resolve(currentToken, new ProjectValue('current'))).assertTrue();
      expect((coordinator.value() as ProjectValue).id).assertEqual('current');
      const hiddenToken = coordinator.begin();
      coordinator.deactivate();
      expect(coordinator.reject(hiddenToken)).assertFalse();
      expect(coordinator.status()).assertEqual(ScreenLoadStatus.IDLE);
    });
  });
}
