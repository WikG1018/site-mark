import { LazyListDataSource } from '../../shared/LazyListDataSource';

export class StableSelectionList<T> {
  readonly data: LazyListDataSource<T>;
  private generation: number = 0;
  private selected: string[] = [];

  constructor(keyOf: (item: T) => string) {
    this.data = new LazyListDataSource<T>(keyOf);
  }

  beginLoad(): number {
    this.generation += 1;
    return this.generation;
  }

  invalidate(): void {
    this.generation += 1;
  }

  replaceFor(generation: number, values: T[]): boolean {
    if (generation !== this.generation) {
      return false;
    }
    this.data.replace(values);
    return true;
  }

  count(): number {
    return this.data.totalCount();
  }

  isSelected(id: string): boolean {
    return this.selected.indexOf(id) >= 0;
  }

  selectedIds(): string[] {
    return this.selected.slice();
  }

  toggle(id: string): void {
    const index = this.selected.indexOf(id);
    if (index >= 0) {
      const next = this.selected.slice();
      next.splice(index, 1);
      this.selected = next;
    } else {
      this.selected = this.selected.concat([id]);
    }
    this.data.replace(this.data.snapshot());
  }
}
