export type CaptureProcessor = (captureId: string) => Promise<void>;

export class SerialCaptureQueue {
  private readonly processor: CaptureProcessor;
  private readonly pendingIds: string[] = [];
  private running: boolean = false;
  private drainWaiters: Array<() => void> = [];
  private startWaiters: Array<() => void> = [];
  private drainedListener: (() => void) | null = null;

  constructor(processor: CaptureProcessor) {
    this.processor = processor;
  }

  enqueue(captureId: string): void {
    const normalized = captureId.trim();
    if (normalized.length === 0) {
      return;
    }
    const existing = this.pendingIds.indexOf(normalized);
    if (existing >= 0) {
      this.pendingIds.splice(existing, 1);
    }
    this.pendingIds.push(normalized);
    if (!this.running) {
      this.running = true;
      Promise.resolve().then((): Promise<void> => this.runLoop());
    }
  }

  isBusy(): boolean {
    return this.running;
  }

  pendingCount(): number {
    return this.pendingIds.length;
  }

  setDrainedListener(listener: (() => void) | null): void {
    this.drainedListener = listener;
  }

  whenIdleStarted(): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      this.startWaiters.push(resolve);
    });
  }

  drain(): Promise<void> {
    if (!this.running && this.pendingIds.length === 0) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void): void => {
      this.drainWaiters.push(resolve);
    });
  }

  private notifyStarted(): void {
    const waiters = this.startWaiters;
    this.startWaiters = [];
    for (const resolve of waiters) {
      resolve();
    }
  }

  private notifyDrained(): void {
    const waiters = this.drainWaiters;
    this.drainWaiters = [];
    for (const resolve of waiters) {
      resolve();
    }
    const listener = this.drainedListener;
    if (listener !== null) {
      listener();
    }
  }

  private async runLoop(): Promise<void> {
    while (this.pendingIds.length > 0) {
      const captureId = this.pendingIds.shift();
      if (captureId === undefined) {
        continue;
      }
      this.notifyStarted();
      try {
        await this.processor(captureId);
      } catch (_) {
        // The processor persists a user-visible failed/retryable state. A
        // single bad item must never poison the serial chain.
      }
    }
    this.running = false;
    this.notifyDrained();
    // An enqueue can arrive between the empty check and setting running=false.
    if (this.pendingIds.length > 0 && !this.running) {
      this.running = true;
      await this.runLoop();
    }
  }
}
