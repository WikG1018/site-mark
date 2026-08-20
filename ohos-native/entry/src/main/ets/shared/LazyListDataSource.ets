export class LazyListDataSource<T> implements IDataSource {
  private items: T[] = [];
  private listeners: DataChangeListener[] = [];
  private readonly keyOf: (item: T) => string;

  constructor(keyOf: (item: T) => string) {
    this.keyOf = keyOf;
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): T {
    if (index < 0 || index >= this.items.length) {
      throw new Error('lazy_list_index_out_of_range');
    }
    return this.items[index];
  }

  snapshot(): T[] {
    return this.items.slice();
  }

  replace(values: T[]): void {
    const previousKeys = this.items.map((item: T): string => this.keyOf(item));
    const nextKeys = values.map((item: T): string => this.keyOf(item));
    const sameOrder = previousKeys.length === nextKeys.length &&
      previousKeys.every((key: string, index: number): boolean => key === nextKeys[index]);
    this.items = values.slice();
    if (!sameOrder) {
      for (const listener of this.listeners) {
        listener.onDataReloaded();
      }
      return;
    }
    for (let index = 0; index < this.items.length; index += 1) {
      for (const listener of this.listeners) {
        listener.onDataChange(index);
      }
    }
  }

  appendUnique(values: T[]): void {
    const keys = new Set<string>(this.items.map((item: T): string => this.keyOf(item)));
    for (const value of values) {
      const key = this.keyOf(value);
      if (keys.has(key)) {
        continue;
      }
      const index = this.items.length;
      this.items.push(value);
      keys.add(key);
      for (const listener of this.listeners) {
        listener.onDataAdd(index);
      }
    }
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
}
