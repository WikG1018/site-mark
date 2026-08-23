import { backgroundTaskManager } from '@kit.BackgroundTasksKit';

export type SuspendDelayRequester = (reason: string, onExpired: () => void) => number;
export type SuspendDelayCanceller = (requestId: number) => void;
export type SuspendDelayBusyQuery = () => boolean;

export function requestSystemSuspendDelay(reason: string, onExpired: () => void): number {
  const info = backgroundTaskManager.requestSuspendDelay(reason, onExpired);
  return info.requestId;
}

export function cancelSystemSuspendDelay(requestId: number): void {
  backgroundTaskManager.cancelSuspendDelay(requestId);
}

export class SuspendDelayWindow {
  private static readonly MAX_RENEWALS: number = 1;

  private readonly reason: string;
  private readonly requester: SuspendDelayRequester;
  private readonly canceller: SuspendDelayCanceller;
  private readonly isBusy: SuspendDelayBusyQuery;
  private activeRequestId: number | null = null;
  private renewalsUsed: number = 0;

  constructor(reason: string, requester: SuspendDelayRequester, canceller: SuspendDelayCanceller,
    isBusy: SuspendDelayBusyQuery) {
    this.reason = reason;
    this.requester = requester;
    this.canceller = canceller;
    this.isBusy = isBusy;
  }

  acquire(): void {
    if (this.activeRequestId !== null || !this.isBusy()) {
      return;
    }
    this.renewalsUsed = 0;
    this.request();
  }

  release(): void {
    const requestId = this.activeRequestId;
    this.activeRequestId = null;
    if (requestId === null) {
      return;
    }
    try {
      this.canceller(requestId);
    } catch (_) {
    }
  }

  isActive(): boolean {
    return this.activeRequestId !== null;
  }

  private request(): void {
    try {
      this.activeRequestId = this.requester(this.reason, (): void => this.handleExpired());
    } catch (_) {
      this.activeRequestId = null;
    }
  }

  private handleExpired(): void {
    if (this.activeRequestId === null || !this.isBusy()) {
      return;
    }
    if (this.renewalsUsed >= SuspendDelayWindow.MAX_RENEWALS) {
      return;
    }
    this.renewalsUsed += 1;
    this.request();
  }
}
