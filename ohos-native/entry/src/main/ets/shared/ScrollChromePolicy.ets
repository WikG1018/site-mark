export class ScrollChromePolicy {
  static readonly HIDE_THRESHOLD: number = 8;
  static readonly SHOW_THRESHOLD: number = 8;
  static readonly TOP_REVEAL_EXTENT: number = 24;

  visible: boolean = true;
  private accumulated: number = 0;

  apply(delta: number, offset: number, forceVisible: boolean = false): boolean {
    if (!Number.isFinite(delta) || !Number.isFinite(offset)) {
      return false;
    }
    if (forceVisible || offset <= ScrollChromePolicy.TOP_REVEAL_EXTENT) {
      this.accumulated = 0;
      return this.setVisible(true);
    }
    if (delta === 0) {
      return false;
    }
    if (this.accumulated !== 0 && Math.sign(delta) !== Math.sign(this.accumulated)) {
      this.accumulated = 0;
    }
    this.accumulated += delta;
    if (this.accumulated >= ScrollChromePolicy.HIDE_THRESHOLD) {
      this.accumulated = 0;
      return this.setVisible(false);
    }
    if (this.accumulated <= -ScrollChromePolicy.SHOW_THRESHOLD) {
      this.accumulated = 0;
      return this.setVisible(true);
    }
    return false;
  }

  reset(): boolean {
    this.accumulated = 0;
    return this.setVisible(true);
  }

  private setVisible(value: boolean): boolean {
    if (this.visible === value) {
      return false;
    }
    this.visible = value;
    return true;
  }
}

export class ScrollChromeCoordinator {
  private static instance: ScrollChromeCoordinator | null = null;
  private readonly policy: ScrollChromePolicy = new ScrollChromePolicy();
  private readonly reasons: Map<string, boolean> = new Map<string, boolean>();
  private forceCount: number = 0;
  private lastOffset: number = 0;
  private hasOffset: boolean = false;
  private listeners: Array<() => void> = [];

  static shared(): ScrollChromeCoordinator {
    if (ScrollChromeCoordinator.instance === null) {
      ScrollChromeCoordinator.instance = new ScrollChromeCoordinator();
    }
    return ScrollChromeCoordinator.instance as ScrollChromeCoordinator;
  }

  static resetShared(): void {
    ScrollChromeCoordinator.instance = null;
  }

  isVisible(): boolean {
    return this.forceCount > 0 || this.policy.visible;
  }

  subscribe(listener: () => void): void {
    this.listeners.push(listener);
  }

  unsubscribe(listener: () => void): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  setForce(reason: string, active: boolean): void {
    const previous = this.reasons.get(reason) === true;
    if (previous === active) {
      return;
    }
    this.reasons.set(reason, active);
    this.forceCount += active ? 1 : -1;
    if (active) {
      this.policy.reset();
    }
    this.emit();
  }

  applyOffset(offset: number): void {
    if (!Number.isFinite(offset)) {
      return;
    }
    if (!this.hasOffset) {
      this.lastOffset = offset;
      this.hasOffset = true;
      return;
    }
    const delta = offset - this.lastOffset;
    this.lastOffset = offset;
    if (this.policy.apply(delta, offset, this.forceCount > 0)) {
      this.emit();
    }
  }

  reset(): void {
    this.hasOffset = false;
    this.lastOffset = 0;
    if (this.policy.reset()) {
      this.emit();
    } else if (this.forceCount > 0) {
      this.emit();
    }
  }

  hiddenTranslateY(height: number): number {
    return this.isVisible() ? 0 : height;
  }

  private emit(): void {
    const copy = this.listeners.slice();
    for (let i = 0; i < copy.length; i++) {
      copy[i]();
    }
  }
}
