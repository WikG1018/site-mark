import { describe, expect, it } from '@ohos/hypium';
import { SerialCaptureQueue } from '../main/ets/background/SerialCaptureQueue';

export default function serialCaptureQueueTest(): void {
  describe('SerialCaptureQueue', () => {
    it('runs one capture at a time and replaces a queued duplicate', 0, async () => {
      const started: string[] = [];
      const released: Array<() => void> = [];
      const queue = new SerialCaptureQueue(async (captureId: string): Promise<void> => {
        started.push(captureId);
        await new Promise<void>((resolve: () => void): void => {
          released.push(resolve);
        });
      });

      queue.enqueue('a');
      queue.enqueue('b');
      queue.enqueue('b');
      await Promise.resolve();
      expect(started.join(',')).assertEqual('a');
      expect(queue.pendingCount()).assertEqual(1);

      released[0]();
      await queue.whenIdleStarted();
      expect(started.join(',')).assertEqual('a,b');
      expect(queue.pendingCount()).assertEqual(0);

      released[1]();
      await queue.drain();
      expect(queue.isBusy()).assertFalse();
    });

    it('continues after one processor failure', 0, async () => {
      const seen: string[] = [];
      const queue = new SerialCaptureQueue(async (captureId: string): Promise<void> => {
        seen.push(captureId);
        if (captureId === 'bad') {
          throw new Error('expected');
        }
      });
      queue.enqueue('bad');
      queue.enqueue('good');
      await queue.drain();
      expect(seen.join(',')).assertEqual('bad,good');
    });
  });
}
