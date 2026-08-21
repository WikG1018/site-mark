export class ListPageCoordinator {
  private active: boolean = false;
  private restorePending: boolean = true;
  private safeReloadRequested: boolean = false;

  activate(): boolean {
    if (this.active) {
      return false;
    }
    this.active = true;
    return true;
  }

  deactivate(): boolean {
    if (!this.active) {
      return false;
    }
    this.active = false;
    return true;
  }

  isActive(): boolean {
    return this.active;
  }

  beginRestore(): void {
    this.restorePending = true;
  }

  completeRestore(): void {
    this.restorePending = false;
  }

  isRestorePending(): boolean {
    return this.restorePending;
  }

  canSaveScroll(): boolean {
    return this.active && !this.restorePending;
  }

  requestSafeReload(): void {
    this.safeReloadRequested = true;
  }

  consumeSafeReloadRequest(): boolean {
    if (!this.safeReloadRequested) {
      return false;
    }
    this.safeReloadRequested = false;
    return true;
  }
}
