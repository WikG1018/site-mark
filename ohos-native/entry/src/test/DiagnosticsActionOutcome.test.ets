import { describe, expect, it } from '@ohos/hypium';
import { DiagnosticsGenerationOutcome, DiagnosticsGenerationOutcomeStore, DiagnosticsGenerationStatus }
  from '../main/ets/feature/settings/DiagnosticsActionOutcome';
import { ScreenLifecycleActionCoordinator } from '../main/ets/shared/ScreenActionCoordinator';

class DeferredSaveResult {
  readonly promise: Promise<boolean>;
  private resolveValue: (value: boolean) => void = (_value: boolean): void => {};
  private rejectValue: (reason: Error) => void = (_reason: Error): void => {};

  constructor() {
    this.promise = new Promise<boolean>((resolve: (value: boolean) => void,
      reject: (reason: Error) => void): void => {
      this.resolveValue = resolve;
      this.rejectValue = reject;
    });
  }

  resolve(value: boolean): void {
    this.resolveValue(value);
  }

  reject(): void {
    this.rejectValue(new Error('controlled failure'));
  }
}

interface ReconciledState {
  message: string;
  messageError: boolean;
}

function outcomeMessage(outcome: DiagnosticsGenerationOutcome): string {
  if (outcome.status === DiagnosticsGenerationStatus.SAVED) return `saved:${outcome.eventCount}`;
  if (outcome.status === DiagnosticsGenerationStatus.CANCELLED) return 'cancelled';
  return 'failed';
}

async function runHiddenGeneration(completion: DeferredSaveResult): Promise<ReconciledState> {
  const coordinator = new ScreenLifecycleActionCoordinator();
  const outcomes = new DiagnosticsGenerationOutcomeStore();
  let message: string = 'progress';
  let messageError: boolean = false;
  coordinator.activate();
  const token: number = coordinator.begin() as number;
  const operation: Promise<void> = (async (): Promise<void> => {
    try {
      const saved: boolean = await completion.promise;
      outcomes.publish(new DiagnosticsGenerationOutcome(saved ? DiagnosticsGenerationStatus.SAVED :
        DiagnosticsGenerationStatus.CANCELLED, 7));
    } catch (_) {
      outcomes.publish(new DiagnosticsGenerationOutcome(DiagnosticsGenerationStatus.FAILED, 0));
    } finally {
      coordinator.finish(token);
    }
  })();

  coordinator.invalidate();
  coordinator.activate();
  const reconcile: Promise<void> = coordinator.whenIdle().then((): void => {
    const outcome: DiagnosticsGenerationOutcome | null = outcomes.consume();
    message = outcome === null ? '' : outcomeMessage(outcome);
    messageError = outcome?.status === DiagnosticsGenerationStatus.FAILED;
  });
  await operation;
  await reconcile;
  return { message, messageError };
}

export default function diagnosticsActionOutcomeTest(): void {
  describe('DiagnosticsActionOutcome', () => {
    it('replaces hidden generation progress with the saved outcome after re-entry', 0, async () => {
      const completion = new DeferredSaveResult();
      const resultPromise: Promise<ReconciledState> = runHiddenGeneration(completion);
      completion.resolve(true);

      const state: ReconciledState = await resultPromise;
      expect(state.message).assertEqual('saved:7');
      expect(state.messageError).assertFalse();
    });

    it('replaces hidden generation progress with the cancelled outcome after re-entry', 0, async () => {
      const completion = new DeferredSaveResult();
      const resultPromise: Promise<ReconciledState> = runHiddenGeneration(completion);
      completion.resolve(false);

      const state: ReconciledState = await resultPromise;
      expect(state.message).assertEqual('cancelled');
      expect(state.messageError).assertFalse();
    });

    it('replaces hidden generation progress with the failed outcome after re-entry', 0, async () => {
      const completion = new DeferredSaveResult();
      const resultPromise: Promise<ReconciledState> = runHiddenGeneration(completion);
      completion.reject();

      const state: ReconciledState = await resultPromise;
      expect(state.message).assertEqual('failed');
      expect(state.messageError).assertTrue();
    });

    it('consumes each completed outcome only once', 0, () => {
      const outcomes = new DiagnosticsGenerationOutcomeStore();
      outcomes.publish(new DiagnosticsGenerationOutcome(DiagnosticsGenerationStatus.SAVED, 2));

      expect(outcomes.consume()?.eventCount).assertEqual(2);
      expect(outcomes.consume() === null).assertTrue();
    });
  });
}
