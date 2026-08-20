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
  private activeToken: number = 0;
  private busy: boolean = false;
  private active: boolean = false;

  activate(): void {
    this.activeToken += 1;
    this.active = true;
    this.busy = false;
  }

  begin(): number | null {
    if (!this.active || this.busy) {
      return null;
    }
    this.activeToken += 1;
    this.busy = true;
    return this.activeToken;
  }

  isCurrent(token: number): boolean {
    return this.active && this.busy && token === this.activeToken;
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
    this.active = false;
    this.busy = false;
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
