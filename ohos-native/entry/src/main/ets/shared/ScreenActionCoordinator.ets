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
