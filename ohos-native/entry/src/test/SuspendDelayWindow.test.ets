import { describe, expect, it } from '@ohos/hypium';
import { SuspendDelayWindow } from '../main/ets/shared/SuspendDelayWindow';

class RequestProbe {
  calls: number = 0;
  lastOnExpired: (() => void) | null = null;

  request(reason: string, onExpired: () => void): number {
    this.calls += 1;
    this.lastOnExpired = onExpired;
    return this.calls;
  }

  fireExpiry(): void {
    if (this.lastOnExpired !== null) {
      this.lastOnExpired();
    }
  }
}

class CancelProbe {
  cancelledIds: number[] = [];

  cancel(requestId: number): void {
    this.cancelledIds.push(requestId);
  }
}

export default function suspendDelayWindowTest(): void {
  describe('SuspendDelayWindow', () => {
    it('acquires once while busy and stays idempotent', 0, () => {
      const requests = new RequestProbe();
      const cancels = new CancelProbe();
      const window = new SuspendDelayWindow('reason', (r: string, e: () => void): number =>
        requests.request(r, e), (id: number): void => cancels.cancel(id), (): boolean => true);
      window.acquire();
      window.acquire();
      expect(window.isActive()).assertTrue();
      expect(requests.calls).assertEqual(1);
    });

    it('skips the request when the queue is idle', 0, () => {
      const requests = new RequestProbe();
      const cancels = new CancelProbe();
      const window = new SuspendDelayWindow('reason', (r: string, e: () => void): number =>
        requests.request(r, e), (id: number): void => cancels.cancel(id), (): boolean => false);
      window.acquire();
      expect(window.isActive()).assertFalse();
      expect(requests.calls).assertEqual(0);
    });

    it('releases the active request exactly once and swallows canceller errors', 0, () => {
      const requests = new RequestProbe();
      const window = new SuspendDelayWindow('reason', (r: string, e: () => void): number =>
        requests.request(r, e), (_id: number): void => {
        throw new Error('already_cancelled');
      }, (): boolean => true);
      window.acquire();
      window.release();
      expect(window.isActive()).assertFalse();
      window.release();
      expect(requests.calls).assertEqual(1);
    });

    it('never cancels without an active request', 0, () => {
      const requests = new RequestProbe();
      const cancels = new CancelProbe();
      const window = new SuspendDelayWindow('reason', (r: string, e: () => void): number =>
        requests.request(r, e), (id: number): void => cancels.cancel(id), (): boolean => true);
      window.release();
      expect(cancels.cancelledIds.length).assertEqual(0);
    });

    it('tolerates requester failures and allows a later retry', 0, () => {
      let failing = true;
      const requests = new RequestProbe();
      const cancels = new CancelProbe();
      const window = new SuspendDelayWindow('reason', (r: string, e: () => void): number => {
        if (failing) {
          throw new Error('system_unavailable');
        }
        return requests.request(r, e);
      }, (id: number): void => cancels.cancel(id), (): boolean => true);
      window.acquire();
      expect(window.isActive()).assertFalse();
      failing = false;
      window.acquire();
      expect(window.isActive()).assertTrue();
      expect(requests.calls).assertEqual(1);
    });

    it('renews at most once per acquisition while still busy', 0, () => {
      const requests = new RequestProbe();
      const cancels = new CancelProbe();
      const window = new SuspendDelayWindow('reason', (r: string, e: () => void): number =>
        requests.request(r, e), (id: number): void => cancels.cancel(id), (): boolean => true);
      window.acquire();
      requests.fireExpiry();
      expect(requests.calls).assertEqual(2);
      requests.fireExpiry();
      expect(requests.calls).assertEqual(2);
      window.release();
      expect(cancels.cancelledIds.length).assertEqual(1);
    });

    it('stops renewing once released or idle', 0, () => {
      const requests = new RequestProbe();
      let busy = true;
      const window = new SuspendDelayWindow('reason', (r: string, e: () => void): number =>
        requests.request(r, e), (_id: number): void => {
      }, (): boolean => busy);
      window.acquire();
      window.release();
      requests.fireExpiry();
      expect(requests.calls).assertEqual(1);
      busy = false;
      window.acquire();
      requests.fireExpiry();
      expect(requests.calls).assertEqual(1);
    });
  });
}
