export class KeyedOperationGate {
  private readonly activeKeys: string[] = [];

  tryEnter(key: string): boolean {
    const normalized = key.trim();
    if (normalized.length === 0 || this.activeKeys.indexOf(normalized) >= 0) {
      return false;
    }
    this.activeKeys.push(normalized);
    return true;
  }

  leave(key: string): void {
    const normalized = key.trim();
    const index = this.activeKeys.indexOf(normalized);
    if (index >= 0) {
      this.activeKeys.splice(index, 1);
    }
  }
}
