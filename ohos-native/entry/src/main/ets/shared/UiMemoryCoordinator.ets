export type UiMemoryListener = (level: number) => void;

export class UiMemoryCoordinator {
  private listeners: UiMemoryListener[] = [];

  register(listener: UiMemoryListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregister(listener: UiMemoryListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  broadcast(level: number): void {
    const snapshot = this.listeners.slice();
    for (const listener of snapshot) {
      try {
        listener(level);
      } catch (_) {
      }
    }
  }
}
