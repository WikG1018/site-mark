export class ScreenActionCoordinator {
  private activeToken: number = 0;
  private busy: boolean = false;

  begin(): number | null {
    if (this.busy) {
      return null;
    }
    this.activeToken += 1;
    this.busy = true;
    return this.activeToken;
  }

  isCurrent(token: number): boolean {
    return this.busy && token === this.activeToken;
  }

  finish(token: number): boolean {
    if (!this.isCurrent(token)) {
      return false;
    }
    this.busy = false;
    return true;
  }

  invalidate(): void {
    this.activeToken += 1;
    this.busy = false;
  }

  isBusy(): boolean {
    return this.busy;
  }
}

export class ScreenLifecycleActionCoordinator {
  private epoch: number = 0;
  private nextActionToken: number = 0;
  private inFlightToken: number = -1;
  private inFlightEpoch: number = -1;
  private active: boolean = false;
  private idleWaiters: Array<() => void> = [];

  activate(): void {
    this.epoch += 1;
    this.active = true;
  }

  begin(): number | null {
    if (!this.active || this.inFlightToken >= 0) {
      return null;
    }
    this.nextActionToken += 1;
    this.inFlightToken = this.nextActionToken;
    this.inFlightEpoch = this.epoch;
    return this.inFlightToken;
  }

  isCurrent(token: number): boolean {
    return this.active && token === this.inFlightToken && this.inFlightEpoch === this.epoch;
  }

  finish(token: number): boolean {
    if (token !== this.inFlightToken) {
      return false;
    }
    const canCommit: boolean = this.isCurrent(token);
    this.inFlightToken = -1;
    this.inFlightEpoch = -1;
    const waiters: Array<() => void> = this.idleWaiters;
    this.idleWaiters = [];
    waiters.forEach((resolve: () => void): void => resolve());
    return canCommit;
  }

  invalidate(): void {
    this.epoch += 1;
    this.active = false;
  }

  isBusy(): boolean {
    return this.inFlightToken >= 0;
  }

  isActive(): boolean {
    return this.active;
  }

  whenIdle(): Promise<void> {
    if (!this.isBusy()) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void): void => {
      this.idleWaiters.push(resolve);
    });
  }
}

export class ScreenRequestCoordinator {
  private generation: number = 0;
  private active: boolean = false;

  activate(): void {
    this.generation += 1;
    this.active = true;
  }

  deactivate(): void {
    this.generation += 1;
    this.active = false;
  }

  begin(): number {
    if (!this.active) {
      return -1;
    }
    this.generation += 1;
    return this.generation;
  }

  isCurrent(token: number): boolean {
    return this.active && token === this.generation;
  }

  isActive(): boolean {
    return this.active;
  }
}
